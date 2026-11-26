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
    let batch = container.appendingPathComponent("Intake", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
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
      let target = Self.unique(batch.appendingPathComponent(name))
      do {
        // The provided file is deleted when this handler returns: copy now.
        try FileManager.default.copyItem(at: url, to: target)
        done(target.lastPathComponent)
      } catch {
        done(nil)
      }
    }
  }

  private static func write(_ text: String, named name: String, in batch: URL) -> String? {
    let target = unique(batch.appendingPathComponent(name))
    do {
      try text.write(to: target, atomically: true, encoding: .utf8)
      return target.lastPathComponent
    } catch {
      return nil
    }
  }

  private static func unique(_ url: URL) -> URL {
    var candidate = url
    var index = 2
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = url.deletingLastPathComponent()
        .appendingPathComponent(ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)")
      index += 1
    }
    return candidate
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
