import AVFoundation
import Flutter
import MediaPlayer
import os
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let log = Logger(subsystem: "io.github.scutlzh684.fideluneP1t2", category: "audio")
  private let session = AVAudioSession.sharedInstance()
  private var bridge: FlutterMethodChannel?
  private var evidence: FileHandle?
  private var hasTrack = false

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "fidelune/p1t2", binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    bridge = channel
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self else {
        reply(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, reply: reply)
    }
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(routeChanged(_:)),
                       name: AVAudioSession.routeChangeNotification, object: session)
    center.addObserver(self, selector: #selector(interrupted(_:)),
                       name: AVAudioSession.interruptionNotification, object: session)
    center.addObserver(self, selector: #selector(servicesReset(_:)),
                       name: AVAudioSession.mediaServicesWereResetNotification, object: session)
    registerRemoteCommands()
  }

  private func handle(_ call: FlutterMethodCall, reply: FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    do {
      switch call.method {
      case "assetDirectory":
        let files = FileManager.default
        let dir = try files.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
          .appendingPathComponent("p1t2", isDirectory: true)
        try files.createDirectory(at: dir, withIntermediateDirectories: true)
        let documents = try files.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let path = documents.appendingPathComponent("p1t2-evidence.jsonl")
        if !files.fileExists(atPath: path.path) {
          try Data().write(to: path)
        }
        let file = try FileHandle(forWritingTo: path)
        try file.seekToEnd()
        evidence = file
        record(["event": "launch", "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?",
                "ios": UIDevice.current.systemVersion, "memoryBytes": memoryBytes()])
        reply(dir.path)
      case "record":
        let sample = args["includeSession"] as? Bool == true ? snapshot() : [:]
        var row = args
        if !sample.isEmpty { row["session"] = sample }
        if args["event"] as? String == "heartbeat" { row["memoryBytes"] = memoryBytes() }
        record(row)
        reply(sample)
      case "capturePath":
        guard let name = call.arguments as? String, ["p1t2-pcm24.wav", "p1t2-gap.wav"].contains(name) else {
          reply(FlutterMethodNotImplemented)
          return
        }
        let documents = try FileManager.default.url(
          for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        reply(documents.appendingPathComponent(name).path)
      case "nowPlaying":
        updateNowPlaying(args)
        reply(nil)
      case "reactivate":
        try session.setActive(true)
        record(["event": "session-reactivated", "session": snapshot()])
        reply(nil)
      default:
        reply(FlutterMethodNotImplemented)
      }
    } catch {
      record(["event": "native-error", "method": call.method,
              "domain": (error as NSError).domain, "code": (error as NSError).code])
      reply(FlutterError(code: "p1t2_native", message: (error as NSError).domain, details: (error as NSError).code))
    }
  }

  private func snapshot() -> [String: Any] {
    [
      "category": session.category.rawValue,
      "categoryOptions": session.categoryOptions.rawValue,
      "mode": session.mode.rawValue,
      "preferredRateHz": session.preferredSampleRate,
      "sampleRateHz": session.sampleRate,
      "outputChannels": session.outputNumberOfChannels,
      "maxOutputChannels": session.maximumOutputNumberOfChannels,
      "ioBufferSeconds": session.ioBufferDuration,
      "outputLatencySeconds": session.outputLatency,
      "route": session.currentRoute.outputs.map { $0.portType.rawValue },
      "volume": session.outputVolume,
    ]
  }

  private func record(_ data: [String: Any]) {
    var row = data
    row["unixTime"] = Date().timeIntervalSince1970
    row["uptimeSeconds"] = ProcessInfo.processInfo.systemUptime
    do {
      var line = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
      line.append(0x0a)
      try evidence?.write(contentsOf: line)
      let text = String(decoding: line.dropLast(), as: UTF8.self)
      log.notice("FIDELUNE_P1T2 \(text, privacy: .public)")
    } catch {
      log.error("FIDELUNE_P1T2 evidence write failed")
    }
  }

  private func memoryBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return status == KERN_SUCCESS ? info.phys_footprint : 0
  }

  private func updateNowPlaying(_ args: [String: Any]) {
    let title = args["track"] as? String ?? ""
    hasTrack = !title.isEmpty
    let center = MPNowPlayingInfoCenter.default()
    guard hasTrack else {
      center.nowPlayingInfo = nil
      return
    }
    center.nowPlayingInfo = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: "Fidelune P1-T2",
      MPMediaItemPropertyPlaybackDuration: args["duration"] ?? 0,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: args["position"] ?? 0,
      MPNowPlayingInfoPropertyPlaybackRate: args["playing"] as? Bool == true ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]
  }

  private func registerRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    func bind(_ remote: MPRemoteCommand, _ name: String) {
      remote.isEnabled = true
      remote.addTarget { [weak self] event in
        let seconds = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
        DispatchQueue.main.async { [weak self] in
          guard let self, self.hasTrack else { return }
          var args: [String: Any] = ["command": name]
          if let seconds { args["seconds"] = seconds }
          self.record(["event": "remote-received", "command": name])
          self.bridge?.invokeMethod("remote", arguments: args)
        }
        return .success
      }
    }
    bind(center.playCommand, "play")
    bind(center.pauseCommand, "pause")
    bind(center.togglePlayPauseCommand, "toggle")
    bind(center.nextTrackCommand, "next")
    bind(center.previousTrackCommand, "previous")
    bind(center.changePlaybackPositionCommand, "seek")
  }

  @objc private func routeChanged(_ note: Notification) {
    let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
    let previous = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
    let route = previous?.outputs.map { $0.portType.rawValue } ?? []
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let unplugged = reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
      self.record(["event": "route", "reason": reason, "previousRoute": route, "session": self.snapshot()])
      self.bridge?.invokeMethod(unplugged ? "unplug" : "route", arguments: [:])
    }
  }

  @objc private func interrupted(_ note: Notification) {
    guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
    let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let args = ["began": interruption == .began,
                  "resume": AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)]
      self.record(["event": "interruption", "flags": args, "session": self.snapshot()])
      self.bridge?.invokeMethod("interruption", arguments: args)
    }
  }

  @objc private func servicesReset(_ note: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.record(["event": "media-services-reset", "session": self.snapshot()])
    }
  }
}
