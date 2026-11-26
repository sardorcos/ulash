import Flutter
import Network
import Photos
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var storageBridge: StorageBridge?
  private var networkBridge: NetworkBridge?
  private var intakeBridge: IntakeBridge?
  private var deviceBridge: DeviceBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    storageBridge = StorageBridge(messenger: messenger)
    networkBridge = NetworkBridge(messenger: messenger)
    intakeBridge = IntakeBridge(messenger: messenger)
    deviceBridge = DeviceBridge(messenger: messenger)
  }
}

/// Export uses the document provider's copy facility. The original committed
/// file remains in Application Support even if export fails or the app exits.
private final class StorageBridge: NSObject, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate {
  private let channel: FlutterMethodChannel
  private var pendingExport: FlutterResult?
  private var backgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]
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
      case "excludeFromBackup": self.excludeFromBackup(call, result: result)
      case "beginBackgroundTask": self.beginBackgroundTask(result: result)
      case "endBackgroundTask": self.endBackgroundTask(call, result: result)
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

  /// Marks a managed directory (staging, prepared copies, received files) as
  /// not to be included in iCloud/iTunes backups. Only directories inside
  /// Application Support or Documents/Ulash are accepted. Returns false when nothing was changed.
  private func excludeFromBackup(_ call: FlutterMethodCall, result: FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String, !path.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "A directory is required.", details: nil))
      return
    }
    do {
      var directory = URL(fileURLWithPath: path, isDirectory: true)
        .resolvingSymlinksInPath().standardizedFileURL
      let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
        appropriateFor: nil, create: false).resolvingSymlinksInPath().standardizedFileURL
      let roots = [try appSupport(), documents.appendingPathComponent("Ulash", isDirectory: true)]
      guard roots.contains(where: { contained(directory, in: $0) && directory.path != $0.path })
          || directory.path == roots[1].path else {
        result(false)
        return
      }
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
        isDirectory.boolValue else {
        result(false)
        return
      }
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
      result(true)
    } catch {
      result(false)
    }
  }

  /// Extra time after the app leaves the foreground, so the current chunk and
  /// its journal entry can be flushed. It never keeps a transfer running in
  /// the background; Dart ends it as soon as the checkpoint is durable.
  private func beginBackgroundTask(result: FlutterResult) {
    // The expiration handler must not capture a mutable identifier: on expiry
    // every outstanding task is ended (there is normally only one).
    let identifier = UIApplication.shared.beginBackgroundTask(withName: "Ulash.checkpoint") { [weak self] in
      self?.expireAllBackgroundTasks()
    }
    guard identifier != .invalid else {
      result(nil)
      return
    }
    backgroundTasks[identifier.rawValue] = identifier
    result(identifier.rawValue)
  }

  private func endBackgroundTask(_ call: FlutterMethodCall, result: FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let id = arguments["id"] as? Int else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "A task id is required.", details: nil))
      return
    }
    finishBackgroundTask(id, expired: false)
    result(nil)
  }

  private func expireAllBackgroundTasks() {
    for id in Array(backgroundTasks.keys) {
      finishBackgroundTask(id, expired: true)
    }
  }

  private func finishBackgroundTask(_ id: Int, expired: Bool) {
    guard let task = backgroundTasks.removeValue(forKey: id) else { return }
    if expired {
      channel.invokeMethod("backgroundTaskExpired", arguments: id)
    }
    UIApplication.shared.endBackgroundTask(task)
  }

  private func sourceURL(_ path: String) throws -> URL {
    let original = URL(fileURLWithPath: path).standardizedFileURL
    let resolved = original.resolvingSymlinksInPath().standardizedFileURL
    // Received files live in Documents/Ulash (visible in Files) since 1.2;
    // earlier builds kept them under Application Support/file-transfer-v1.
    let legacy = try appSupport().appendingPathComponent("file-transfer-v1", isDirectory: true)
    let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
      appropriateFor: nil, create: false).resolvingSymlinksInPath().standardizedFileURL
      .appendingPathComponent("Ulash", isDirectory: true)
    guard let root = [documents, legacy].first(where: { contained(resolved, in: $0) }) else {
      throw NSError(domain: "FileTransferExport", code: 1)
    }
    let values = try original.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard resolved.path != root.path,
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

/// Local Network privacy state. iOS has no API that reads the decision, so a
/// short Bonjour browse is used: PolicyDenied (-65570) while browsing means
/// the user declined; a browse result or a ready browser means access works.
/// Anything else is "unknown" and must not be shown as a denial.
private final class NetworkBridge: NSObject {
  private static let policyDenied = -65570
  private let channel: FlutterMethodChannel
  private var browser: NWBrowser?
  private var waiting: [FlutterResult] = []
  private var lastState: String = "unknown"
  private var timeout: DispatchWorkItem?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "file_transfer/network", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "localNetworkStatus": self.localNetworkStatus(result)
      case "openSettings": self.openSettings(result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func localNetworkStatus(_ result: @escaping FlutterResult) {
    waiting.append(result)
    // Concurrent calls share one probe.
    guard browser == nil else { return }
    lastState = "unknown"
    let browser = NWBrowser(
      for: .bonjour(type: "_xferapp._tcp", domain: nil), using: NWParameters())
    self.browser = browser
    browser.stateUpdateHandler = { [weak self] state in
      DispatchQueue.main.async { self?.observe(state) }
    }
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      guard !results.isEmpty else { return }
      DispatchQueue.main.async { self?.finish("granted") }
    }
    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.finish(self.lastState)
    }
    timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    browser.start(queue: .main)
  }

  private func observe(_ state: NWBrowser.State) {
    switch state {
    case .ready:
      lastState = "granted"
    case .waiting(let error):
      // While the system prompt is visible the browser can also wait with
      // PolicyDenied, so the final answer is taken when the probe ends.
      lastState = Self.isPolicyDenied(error) ? "denied" : "unknown"
    case .failed(let error):
      finish(Self.isPolicyDenied(error) ? "denied" : "unknown")
    default:
      break
    }
  }

  private static func isPolicyDenied(_ error: NWError) -> Bool {
    if case .dns(let code) = error { return Int(code) == policyDenied }
    return false
  }

  private func finish(_ status: String) {
    timeout?.cancel()
    timeout = nil
    browser?.stateUpdateHandler = nil
    browser?.browseResultsChangedHandler = nil
    browser?.cancel()
    browser = nil
    let results = waiting
    waiting = []
    for result in results { result(status) }
  }

  private func openSettings(_ result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
  }
}


// MARK: - Intake ("Open in Ulash" and the Share Extension)

/// A file URL handed to Ulash by another app. `openInPlace` comes from
/// UIOpenURLContext.options: true means the URL is the user's ORIGINAL
/// document (another app's folder, iCloud Drive, a file provider).
struct IntakeSource {
  let url: URL
  let openInPlace: Bool
}

/// Collects files handed to Ulash from other apps. "Open in" files are copied
/// into tmp/Intake; the Share Extension writes complete batches into the App
/// Group container. `takePending` moves both into tmp/IntakeTaken and returns
/// them once; Dart stages (adopts) them and deletes what it no longer needs.
final class IntakeStore {
  static let shared = IntakeStore()
  static let appGroup = "group.uz.ulash.app"
  /// Abandoned (never completed) extension batches and taken copies Dart did
  /// not clean up are removed after this age. Complete batches that were
  /// never taken are kept for a week, then dropped (the originals are intact).
  static let staleAge: TimeInterval = 24 * 60 * 60
  static let untakenAge: TimeInterval = 7 * 24 * 60 * 60
  /// Called on the main thread whenever new items may be waiting.
  var onAvailable: (() -> Void)?
  private let io = DispatchQueue(label: "uz.ulash.intake")

  private var tmp: URL { FileManager.default.temporaryDirectory }
  private var intakeRoot: URL { tmp.appendingPathComponent("Intake", isDirectory: true) }
  private var takenRoot: URL { tmp.appendingPathComponent("IntakeTaken", isDirectory: true) }

  var groupIntakeRoot: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: IntakeStore.appGroup)?
      .appendingPathComponent("Intake", isDirectory: true)
  }

  /// Ulash's own Documents/Inbox, where iOS places "Copy to Ulash" copies.
  private var ownInbox: URL? {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
      .appendingPathComponent("Inbox", isDirectory: true)
  }

  /// Copies opened files into the intake folder with a coordinated read
  /// (security-scoped when needed; iCloud-only files are downloaded first).
  /// The source is deleted ONLY when it is a copy iOS made inside Ulash's own
  /// Documents/Inbox and the URL was not opened in place. A user's original
  /// is never removed.
  func accept(_ sources: [IntakeSource]) {
    io.async {
      let fm = FileManager.default
      let batch = self.intakeRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try? fm.createDirectory(at: batch, withIntermediateDirectories: true)
      var copied = 0
      for source in sources where source.url.isFileURL {
        let url = source.url
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var ok = false
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
          readingItemAt: url, options: [.withoutChanges], error: &coordinationError
        ) { readable in
          let values = try? readable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
          guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return }
          let name = IntakeStore.safeName(url.lastPathComponent)
          guard let target = IntakeStore.reserve(batch.appendingPathComponent(name)) else { return }
          do {
            // `reserve` created an empty placeholder; replace it with the copy.
            try fm.removeItem(at: target)
            try fm.copyItem(at: readable, to: target)
            ok = true
          } catch {
            try? fm.removeItem(at: target)
          }
        }
        guard ok, coordinationError == nil else { continue }
        copied += 1
        if !source.openInPlace, let inbox = self.ownInbox, IntakeStore.isInside(url, inbox) {
          try? fm.removeItem(at: url)
        }
      }
      if copied == 0 { try? fm.removeItem(at: batch) }
      if copied > 0 { DispatchQueue.main.async { self.onAvailable?() } }
    }
  }

  /// True when `child` (after resolving symlinks and `..`) lies strictly below `root`.
  static func isInside(_ child: URL, _ root: URL) -> Bool {
    let childParts = child.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    let rootParts = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    return childParts.count > rootParts.count && Array(childParts.prefix(rootParts.count)) == rootParts
  }

  /// Removes stale intake leftovers: abandoned extension batches, week-old
  /// untaken batches and day-old taken copies. Runs on the intake queue.
  private func pruneStale() {
    let fm = FileManager.default
    let now = Date()
    func age(_ url: URL) -> TimeInterval {
      let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
      let date = values?.creationDate ?? values?.contentModificationDate ?? now
      return now.timeIntervalSince(date)
    }
    if let root = groupIntakeRoot,
      let batches = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]) {
      for batch in batches {
        let complete = fm.fileExists(atPath: batch.appendingPathComponent(".complete").path)
        if age(batch) > (complete ? IntakeStore.untakenAge : IntakeStore.staleAge) {
          try? fm.removeItem(at: batch)
        }
      }
    }
    if let taken = try? fm.contentsOfDirectory(at: takenRoot, includingPropertiesForKeys: [.creationDateKey]) {
      for batch in taken where age(batch) > IntakeStore.staleAge { try? fm.removeItem(at: batch) }
    }
  }

  func pendingCount() -> Int {
    io.sync { countFiles(in: intakeRoot) + completeGroupBatches().reduce(0) { $0 + countFiles(in: $1) } }
  }

  /// Returns every pending file exactly once as [{path, name}].
  func takePending() -> [[String: String]] {
    io.sync {
      pruneStale()
      let fm = FileManager.default
      try? fm.createDirectory(at: takenRoot, withIntermediateDirectories: true)
      var sources: [URL] = []
      if let batches = try? fm.contentsOfDirectory(at: intakeRoot, includingPropertiesForKeys: nil) {
        sources.append(contentsOf: batches)
      }
      sources.append(contentsOf: completeGroupBatches())
      var result: [[String: String]] = []
      for batch in sources {
        let destination = takenRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
          try fm.createDirectory(at: destination, withIntermediateDirectories: true)
          let files = try fm.contentsOfDirectory(at: batch, includingPropertiesForKeys: [.isRegularFileKey])
          for file in files where !file.lastPathComponent.hasPrefix(".") {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
              continue
            }
            if file.lastPathComponent == "manifest.json" { continue }
            let target = IntakeStore.unique(destination.appendingPathComponent(file.lastPathComponent))
            // Moving out of the App Group container works within the same volume;
            // fall back to a copy if it does not.
            do { try fm.moveItem(at: file, to: target) } catch { try fm.copyItem(at: file, to: target) }
            result.append(["path": target.path, "name": target.lastPathComponent])
          }
          try? fm.removeItem(at: batch)
        } catch {
          continue
        }
      }
      return result
    }
  }

  func hasGroupItems() -> Bool { io.sync { !completeGroupBatches().isEmpty } }

  /// Only batches the extension finished writing (marker file `.complete`).
  private func completeGroupBatches() -> [URL] {
    guard let root = groupIntakeRoot,
      let batches = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    else { return [] }
    return batches.filter {
      FileManager.default.fileExists(atPath: $0.appendingPathComponent(".complete").path)
    }
  }

  private func countFiles(in root: URL) -> Int {
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
    else { return 0 }
    var count = 0
    for case let url as URL in enumerator
    where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      && !url.lastPathComponent.hasPrefix(".") && url.lastPathComponent != "manifest.json" {
      count += 1
    }
    return count
  }

  static func safeName(_ raw: String) -> String {
    let cleaned = raw.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty || cleaned.hasPrefix(".") ? "file" + cleaned : cleaned
  }

  /// Atomically claims a free name (`name`, `name 2`, …) by creating an empty
  /// file with O_EXCL, so concurrent writers never pick the same name.
  static func reserve(_ url: URL) -> URL? {
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    for index in 1...10_000 {
      let name = index == 1 ? url.lastPathComponent
        : (ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)")
      let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
      let fd = Darwin.open(candidate.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
      if fd >= 0 {
        Darwin.close(fd)
        return candidate
      }
      if errno != EEXIST { return nil }
    }
    return nil
  }

  static func unique(_ url: URL) -> URL {
    var candidate = url
    var index = 2
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    while FileManager.default.fileExists(atPath: candidate.path) {
      let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
      candidate = url.deletingLastPathComponent().appendingPathComponent(name)
      index += 1
    }
    return candidate
  }
}

private final class IntakeBridge: NSObject {
  private let channel: FlutterMethodChannel
  private var observer: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "file_transfer/intake", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "takePending": result(IntakeStore.shared.takePending())
      case "pendingCount": result(IntakeStore.shared.pendingCount())
      default: result(FlutterMethodNotImplemented)
      }
    }
    IntakeStore.shared.onAvailable = { [weak self] in
      self?.channel.invokeMethod("intakeAvailable", arguments: nil)
    }
    // The Share Extension cannot wake the app; check when it becomes active.
    observer = NotificationCenter.default.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      if IntakeStore.shared.hasGroupItems() {
        self?.channel.invokeMethod("intakeAvailable", arguments: nil)
      }
    }
  }

  deinit {
    if let observer = observer { NotificationCenter.default.removeObserver(observer) }
  }
}

// MARK: - Device utilities (Photos, secure screen, sensitive clipboard)

private final class DeviceBridge: NSObject {
  private let channel: FlutterMethodChannel
  private var secureScreen = false
  private var shield: UIView?
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "file_transfer/device", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "saveToPhotos": self.saveToPhotos(arguments, result: result)
      case "setSecureScreen":
        self.secureScreen = arguments["enabled"] as? Bool ?? false
        if !self.secureScreen { self.removeShield() }
        result(true)
      case "copySensitive": self.copySensitive(arguments, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: UIScene.willDeactivateNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard let self = self, self.secureScreen, let scene = note.object as? UIWindowScene else { return }
      self.addShield(to: scene)
    })
    observers.append(center.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.removeShield()
    })
  }

  deinit {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
  }

  /// Hides content (e.g. a pairing QR code) from the app switcher snapshot.
  private func addShield(to scene: UIWindowScene) {
    guard shield == nil, let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
    else { return }
    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    blur.frame = window.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(blur)
    shield = blur
  }

  private func removeShield() {
    shield?.removeFromSuperview()
    shield = nil
  }

  private func copySensitive(_ arguments: [String: Any], result: FlutterResult) {
    guard let text = arguments["text"] as? String else {
      result(false)
      return
    }
    let seconds = max(10, min(arguments["seconds"] as? Int ?? 120, 600))
    // localOnly keeps it off Universal Clipboard; it expires automatically.
    UIPasteboard.general.setItems(
      [[UTType.plainText.identifier: text]],
      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(TimeInterval(seconds))])
    result(true)
  }

  private func saveToPhotos(_ arguments: [String: Any], result: @escaping FlutterResult) {
    guard let path = arguments["path"] as? String, !path.isEmpty else {
      result("failed")
      return
    }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().standardizedFileURL.path
    let resolved = url.resolvingSymlinksInPath().path
    guard resolved.hasPrefix(home + "/"), FileManager.default.isReadableFile(atPath: resolved) else {
      result("failed")
      return
    }
    let isVideo = (arguments["kind"] as? String) == "video"
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async { result("denied") }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: isVideo ? .video : .photo, fileURL: URL(fileURLWithPath: resolved), options: nil)
      }) { success, _ in
        DispatchQueue.main.async { result(success ? "saved" : "failed") }
      }
    }
  }
}
