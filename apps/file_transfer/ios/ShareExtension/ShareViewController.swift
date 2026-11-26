import UIKit
import UniformTypeIdentifiers

/// "Share → Ulash": copies the shared photos, videos, files, links and text
/// into the App Group container (Intake/<uuid>/). The main app picks the batch
/// up the next time it becomes active and adds it to the send selection.
/// Nothing is sent from the extension itself.
final class ShareViewController: UIViewController {
  private static let appGroup = "group.uz.ulash.app"
  private let card = UIView()
  private let label = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private var finished = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor.black.withAlphaComponent(0.25)
    card.backgroundColor = .secondarySystemBackground
    card.layer.cornerRadius = 18
    card.translatesAutoresizingMaskIntoConstraints = false
    label.text = Self.text("adding")
    label.numberOfLines = 0
    label.textAlignment = .center
    label.font = UIFont.preferredFont(forTextStyle: .body)
    label.adjustsFontForContentSizeCategory = true
    let stack = UIStackView(arrangedSubviews: [spinner, label])
    stack.axis = .vertical
    stack.spacing = 12
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(stack)
    view.addSubview(card)
    NSLayoutConstraint.activate([
      card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      card.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
      card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
      stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
    ])
    spinner.startAnimating()
    collect()
  }

  private func collect() {
    guard let container = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else {
      finish(Self.text("unavailable"))
      return
    }
    let intake = container.appendingPathComponent("Intake", isDirectory: true)
    Self.pruneStale(intake)
    let batch = intake.appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
    } catch {
      finish(Self.text("failed"))
      return
    }
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    let group = DispatchGroup()
    let lock = NSLock()
    var names: [String] = []
    var textIndex = 0
    for provider in providers {
      group.enter()
      save(provider, into: batch, nextTextIndex: {
        lock.lock(); defer { lock.unlock() }
        textIndex += 1
        return textIndex
      }) { name in
        if let name = name {
          lock.lock()
          names.append(name)
          lock.unlock()
        }
        group.leave()
      }
    }
    group.notify(queue: .main) {
      guard !names.isEmpty else {
        try? FileManager.default.removeItem(at: batch)
        self.finish(Self.text("failed"))
        return
      }
      if let data = try? JSONSerialization.data(withJSONObject: ["files": names]) {
        try? data.write(to: batch.appendingPathComponent("manifest.json"))
      }
      // The marker is written last: the app only takes complete batches.
      FileManager.default.createFile(atPath: batch.appendingPathComponent(".complete").path, contents: Data())
      self.finish(Self.text("added"))
    }
  }

  private func save(
    _ provider: NSItemProvider, into batch: URL, nextTextIndex: @escaping () -> Int,
    done: @escaping (String?) -> Void
  ) {
    let types = provider.registeredTypeIdentifiers
    // Real file data: anything conforming to public.data that is not merely a
    // link or a text snippet. Text *files* still arrive with a file URL.
    func isPayload(_ identifier: String) -> Bool {
      guard let type = UTType(identifier) else { return false }
      return type.conforms(to: .data) && !type.conforms(to: .url) && !type.conforms(to: .text)
    }
    let hasFileURL = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    let isFile = hasFileURL || types.contains(where: isPayload)
    if !isFile, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        guard let url = url else { return done(nil) }
        let content = "[InternetShortcut]\r\nURL=\(url.absoluteString)\r\n"
        let index = nextTextIndex()
        done(Self.write(content, named: index == 1 ? "Link.url" : "Link \(index).url", in: batch))
      }
      return
    }
    if !isFile, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      _ = provider.loadObject(ofClass: String.self) { text, _ in
        guard let text = text else { return done(nil) }
        let index = nextTextIndex()
        done(Self.write(text, named: index == 1 ? "Text.txt" : "Text \(index).txt", in: batch))
      }
      return
    }
    // Prefer the original representation (e.g. HEIC/MOV from Photos): the
    // first registered type that is real data, never a transcoded preview.
    guard let type = types.first(where: isPayload)
      ?? types.first(where: { UTType($0)?.conforms(to: .data) == true && $0 != UTType.fileURL.identifier })
      ?? types.first(where: { UTType($0)?.conforms(to: .item) == true && $0 != UTType.fileURL.identifier })
    else {
      return done(nil)
    }
    provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
      guard let url = url else { return done(nil) }
      var name = provider.suggestedName ?? url.deletingPathExtension().lastPathComponent
      name = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
      if name.isEmpty || name.hasPrefix(".") { name = "file" + name }
      let ext = url.pathExtension.isEmpty
        ? (UTType(type)?.preferredFilenameExtension ?? "") : url.pathExtension
      if !ext.isEmpty && (name as NSString).pathExtension.lowercased() != ext.lowercased() {
        name += "." + ext
      }
      guard let target = Self.reserve(batch.appendingPathComponent(name)) else { return done(nil) }
      // The provided file is deleted when this handler returns: copy now, to
      // a hidden temporary name, then rename over the reserved placeholder.
      let partial = batch.appendingPathComponent(".partial-\(UUID().uuidString)")
      do {
        try FileManager.default.copyItem(at: url, to: partial)
        guard Darwin.rename(partial.path, target.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        done(target.lastPathComponent)
      } catch {
        try? FileManager.default.removeItem(at: partial)
        try? FileManager.default.removeItem(at: target)
        done(nil)
      }
    }
  }

  private static func write(_ text: String, named name: String, in batch: URL) -> String? {
    guard let target = reserve(batch.appendingPathComponent(name)) else { return nil }
    do {
      // Atomic write: a temporary file renamed over the reserved placeholder.
      try text.write(to: target, atomically: true, encoding: .utf8)
      return target.lastPathComponent
    } catch {
      try? FileManager.default.removeItem(at: target)
      return nil
    }
  }

  /// Atomically claims a free name (`name`, `name 2`, …) by creating an empty
  /// file with O_EXCL: providers finish concurrently and may share a name.
  private static func reserve(_ url: URL) -> URL? {
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

  /// Same policy as the app's IntakeStore: batches the extension never
  /// finished are dropped after 24 h; complete batches the app never took
  /// after 7 days (the originals stay in the sharing app).
  private static func pruneStale(_ intake: URL) {
    let fm = FileManager.default
    guard let batches = try? fm.contentsOfDirectory(
      at: intake, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey])
    else { return }
    let now = Date()
    for batch in batches {
      let values = try? batch.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
      let age = now.timeIntervalSince(values?.creationDate ?? values?.contentModificationDate ?? now)
      let complete = fm.fileExists(atPath: batch.appendingPathComponent(".complete").path)
      if age > (complete ? 7 * 24 * 60 * 60 : 24 * 60 * 60) { try? fm.removeItem(at: batch) }
    }
  }

  private func finish(_ message: String) {
    guard !finished else { return }
    finished = true
    spinner.stopAnimating()
    spinner.isHidden = true
    label.text = message
    UIAccessibility.post(notification: .announcement, argument: message)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
      self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
  }

  private static func text(_ key: String) -> String {
    let language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
    let table: [String: [String: String]] = [
      "ru": [
        "adding": "Добавляем в Ulash…",
        "added": "Добавлено в Ulash — откройте приложение, чтобы отправить.",
        "failed": "Не удалось добавить файлы. Попробуйте ещё раз.",
        "unavailable": "Обновите Ulash и откройте его один раз, затем повторите.",
      ],
      "uz": [
        "adding": "Ulash’ga qoʻshilmoqda…",
        "added": "Ulash’ga qoʻshildi — yuborish uchun ilovani oching.",
        "failed": "Fayllarni qoʻshib boʻlmadi. Qayta urinib koʻring.",
        "unavailable": "Ulash’ni yangilang va bir marta oching, soʻng qayta urinib koʻring.",
      ],
      "en": [
        "adding": "Adding to Ulash…",
        "added": "Added to Ulash — open the app to send.",
        "failed": "Couldn’t add the files. Please try again.",
        "unavailable": "Update Ulash and open it once, then try again.",
      ],
    ]
    return table[language]?[key] ?? table["en"]![key]!
  }
}
