import CryptoKit
import Flutter
import os
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private let log = OSLog(subsystem: "io.github.scutlzh684.fideluneP1t1", category: "probe")
  private var folderResult: FlutterResult?
  private let files = FileManager.default
  private let wavHeader = Data([
    82, 73, 70, 70, 52, 0, 0, 0, 87, 65, 86, 69,
    102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0,
    64, 31, 0, 0, 128, 62, 0, 0, 2, 0, 16, 0,
    100, 97, 116, 97, 16, 0, 0, 0,
  ])

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "fidelune/p1t1", binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      let directory = try probeDirectory()
      switch call.method {
      case "inspect":
        break
      case "seed":
        try seed(directory)
      case "chooseFolder":
        let window = UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .flatMap { $0.windows }
          .first { $0.isKeyWindow }
        guard let root = window?.rootViewController, folderResult == nil else {
          result(FlutterError(code: "picker_unavailable", message: nil, details: nil))
          return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        folderResult = result
        root.present(picker, animated: true)
        return
      case "log":
        os_log("FIDELUNE_P1T1 diagnostic marker", log: log, type: .default)
      case "crash":
        os_log("FIDELUNE_P1T1 controlled crash", log: log, type: .default)
        controlledCrash()
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(snapshot(directory))
    } catch {
      result(FlutterError(code: "fixture_io", message: nil, details: nil))
    }
  }

  private func probeDirectory() throws -> URL {
    try files.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("p1t1", isDirectory: true)
  }

  private func seed(_ directory: URL) throws {
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    let media = directory.appendingPathComponent("fixture.wav")
    if !files.fileExists(atPath: media.path) {
      var wav = wavHeader
      withUnsafeBytes(of: UUID().uuid) { wav.append(contentsOf: $0) }
      try wav.write(to: media, options: .atomic)
    }
    let organization = directory.appendingPathComponent("organization.json")
    if !files.fileExists(atPath: organization.path) {
      let entry = ["album": "Fidelune P1-T1", "marker": UUID().uuidString]
      try JSONEncoder().encode(entry).write(to: organization, options: .atomic)
    }
  }

  private func snapshot(_ directory: URL) -> [String: String] {
    let media = directory.appendingPathComponent("fixture.wav")
    let organization = directory.appendingPathComponent("organization.json")
    let bookmark = directory.appendingPathComponent("folder.bookmark")
    var state = [
      "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
      "media": files.fileExists(atPath: media.path) ? "无法校验" : "未写入",
      "organization": files.fileExists(atPath: organization.path) ? "无法校验" : "未写入",
      "bookmark": files.fileExists(atPath: bookmark.path) ? "无法校验" : "未选择",
    ]
    if let bytes = try? Data(contentsOf: media),
      bytes.count == wavHeader.count + 16, bytes.starts(with: wavHeader) {
      state["media"] = digest(bytes)
    }
    if let bytes = try? Data(contentsOf: organization),
      let entry = try? JSONDecoder().decode([String: String].self, from: bytes),
      entry["album"] == "Fidelune P1-T1", let marker = entry["marker"], UUID(uuidString: marker) != nil {
      state["organization"] = String(marker.prefix(8))
    }
    if let bytes = try? Data(contentsOf: bookmark) {
      state["bookmark"] = readBookmark(bytes)
    }
    return state
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
  }

  private func readBookmark(_ bytes: Data) -> String {
    var stale = false
    guard let url = try? URL(
      resolvingBookmarkData: bytes, options: [], relativeTo: nil, bookmarkDataIsStale: &stale
    ), !stale, url.startAccessingSecurityScopedResource() else {
      return "无法恢复访问"
    }
    defer { url.stopAccessingSecurityScopedResource() }
    guard let entries = try? files.contentsOfDirectory(
      at: url, includingPropertiesForKeys: nil
    ) else {
      return "无法读取外部目录"
    }
    return entries.contains { $0.lastPathComponent == "P1T1-marker" }
      ? digest(bytes) + " · 标记可读" : "外部目录缺少 P1T1-marker"
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    defer { folderResult = nil }
    guard let url = urls.first, url.startAccessingSecurityScopedResource() else {
      folderResult?(FlutterError(code: "folder_access", message: nil, details: nil))
      return
    }
    defer { url.stopAccessingSecurityScopedResource() }
    do {
      let directory = try probeDirectory()
      let bytes = try url.bookmarkData(options: .minimalBookmark)
      try files.createDirectory(at: directory, withIntermediateDirectories: true)
      try bytes.write(to: directory.appendingPathComponent("folder.bookmark"), options: .atomic)
      folderResult?(snapshot(directory))
    } catch {
      folderResult?(FlutterError(code: "bookmark_io", message: nil, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    folderResult?(nil)
    folderResult = nil
  }

  @inline(never)
  private func controlledCrash() -> Never {
    fatalError("FIDELUNE_P1T1_CONTROLLED_CRASH")
  }
}
