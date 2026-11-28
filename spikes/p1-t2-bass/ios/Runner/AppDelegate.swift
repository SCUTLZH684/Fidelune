import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    private let logger = DiagnosticsLogger.shared
    private lazy var sessionManager = DacSessionManager(logger: logger)
    private lazy var bassEngine = BassAudioEngine(sessionManager: sessionManager, logger: logger)
    private lazy var nowPlaying = NowPlayingAndRemoteController(logger: logger)
    private lazy var coordinator = PlaybackQueueCoordinator(
        backend: bassEngine,
        sessionManager: sessionManager,
        nowPlaying: nowPlaying,
        logger: logger
    )
    private lazy var selfTestRunner = BassSelfTestRunner(logger: logger)

    private var methodChannel: FlutterMethodChannel?
    private var eventSink: FlutterEventSink?
    private var fixturesDirectoryURL: URL?
    private let fixturesLock = NSLock()

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        sessionManager.configureBindings(
            bassRateProvider: { [weak self] in self?.bassEngine.currentBassDeviceRateHz ?? 0 },
            isPlayingProvider: { [weak self] in self?.bassEngine.isPlaying ?? false }
        )
        coordinator.listener = self
        _ = logger.prepareStorage()
        logger.log(
            event: "app-launch",
            category: "lifecycle",
            message: "Implicit Flutter engine initialized (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?"))",
            fields: [
                "build": "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?")",
                "ios": UIDevice.current.systemVersion,
            ]
        )

        let messenger = engineBridge.applicationRegistrar.messenger()
        let method = FlutterMethodChannel(name: "fidelune/bass_audio", binaryMessenger: messenger)
        self.methodChannel = method
        method.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(FlutterMethodNotImplemented)
                return
            }
            self.handleMethodCall(call, result: result)
        }

        let events = FlutterEventChannel(name: "fidelune/bass_events", binaryMessenger: messenger)
        events.setStreamHandler(self)

        // Warm up BASS engine off main thread so UIKit/Flutter first frame never waits.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.coordinator.initializeEngine()
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "initialize":
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let fixturesURL = self.stageBundledFixtures()
                self.fixturesDirectoryURL = fixturesURL
                let initialized = self.coordinator.initializeEngine()
                let userTracks = self.scanUserMusicTracks()
                let bundledTracks = self.loadBundledTracks(fixturesURL: fixturesURL)
                DispatchQueue.main.async {
                    result([
                        "initialized": initialized,
                        "fixturesPath": fixturesURL?.path ?? "",
                        "bundledTracks": bundledTracks,
                        "userTracks": userTracks,
                        "state": self.coordinator.statePayload(),
                    ])
                }
            }

        case "runAutomatedSelfTests":
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let fixturesURL = self.fixturesDirectoryURL ?? self.stageBundledFixtures()
                guard let dir = fixturesURL else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "no_fixtures", message: "未找到测试音源目录", details: nil))
                    }
                    return
                }
                let results = self.selfTestRunner.runAll(fixturesDirectory: dir)
                DispatchQueue.main.async {
                    result(results.map { $0.toDictionary() })
                }
            }

        case "playQueue":
            let rawTracks = args["tracks"] as? [[String: Any]] ?? []
            let tracks = rawTracks.compactMap { TrackSpec(dictionary: $0) }
            let startIndex = args["startIndex"] as? Int ?? 0
            let startPos = args["startPositionSeconds"] as? Double ?? 0
            let dsdOverride = (args["dsdMode"] as? String).flatMap { DsdOutputMode(rawValue: $0) }
            coordinator.playQueue(
                tracks: tracks,
                startIndex: startIndex,
                startPositionSeconds: startPos,
                dsdModeOverride: dsdOverride
            )
            result(coordinator.statePayload())

        case "play":
            coordinator.play()
            result(nil)

        case "pause":
            coordinator.pause()
            result(nil)

        case "togglePlayPause":
            coordinator.togglePlayPause()
            result(nil)

        case "stop":
            coordinator.stop(reason: "user_stop")
            result(nil)

        case "next":
            coordinator.next(manual: true)
            result(nil)

        case "previous":
            coordinator.previous()
            result(nil)

        case "seek":
            let sec = (args["seconds"] as? NSNumber)?.doubleValue ?? 0
            coordinator.seek(to: sec)
            result(nil)

        case "setPlaybackMode":
            if let raw = args["mode"] as? String, let mode = PlaybackMode(rawValue: raw) {
                coordinator.setPlaybackMode(mode)
            }
            result(nil)

        case "setDsdMode":
            if let raw = args["mode"] as? String, let mode = DsdOutputMode(rawValue: raw) {
                coordinator.setDsdMode(mode)
            }
            result(nil)

        case "acknowledgeDopSafety":
            let ack = args["acknowledged"] as? Bool ?? false
            coordinator.setDopSafetyAcknowledged(ack)
            result(nil)

        case "updateSettings":
            coordinator.updateSettings(args)
            result(coordinator.statePayload())

        case "probeDacSampleRate":
            let hz = args["hz"] as? Int ?? 48000
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let res = self.coordinator.probeDacRate(hz)
                DispatchQueue.main.async {
                    result(res.toDictionary())
                }
            }

        case "runUsbDacRateSweep":
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let results = self.coordinator.runUsbDacRateSweep()
                DispatchQueue.main.async {
                    result(results.map { $0.toDictionary() })
                }
            }

        case "getState":
            result(coordinator.statePayload())

        case "scanUserMusicFolder":
            result(scanUserMusicTracks())

        case "getRecentLogs":
            let limit = args["limit"] as? Int ?? 200
            result(logger.recentEvents(limit: limit))

        case "exportPcmCaptures":
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, let dir = self.fixturesDirectoryURL ?? self.stageBundledFixtures() else {
                    DispatchQueue.main.async { result([:]) }
                    return
                }
                let paths = self.selfTestRunner.exportPcmCaptureWavs(fixturesDirectory: dir)
                DispatchQueue.main.async { result(paths) }
            }

        case "exportReportAndShare":
            let md = args["markdown"] as? String ?? ""
            let json = args["json"] as? String ?? "{}"
            guard let exportedURL = logger.exportBundle(reportMarkdown: md, reportJson: json) else {
                result(FlutterError(code: "export_failed", message: "导出验收报告失败", details: nil))
                return
            }
            let folder = exportedURL.deletingLastPathComponent()
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [exportedURL]
            presentShareSheet(for: files)
            result(folder.path)

        case "saveAcceptanceState":
            let json = args["json"] as? String ?? "{}"
            result(writeAcceptanceState(json: json))

        case "loadAcceptanceState":
            result(readAcceptanceState())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Fixtures & Local Library Helpers

    private func stageBundledFixtures() -> URL? {
        fixturesLock.lock()
        defer { fixturesLock.unlock() }
        let fm = FileManager.default
        guard let cacheBase = try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        let targetDir = cacheBase.appendingPathComponent("fidelune-fixtures", isDirectory: true)
        try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Locate flutter_assets/fixtures inside App.framework or main bundle
        let candidateDirs = [
            Bundle.main.bundleURL.appendingPathComponent("Frameworks/App.framework/flutter_assets/fixtures"),
            Bundle.main.bundleURL.appendingPathComponent("flutter_assets/fixtures"),
        ]
        guard let sourceDir = candidateDirs.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }) else {
            return nil
        }

        let sourceManifest = sourceDir.appendingPathComponent("manifest.json")
        let destManifest = targetDir.appendingPathComponent("manifest.json")
        let sameManifest = (try? Data(contentsOf: sourceManifest)) == (try? Data(contentsOf: destManifest))

        if !sameManifest, let items = try? fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil) {
            for item in items {
                let dst = targetDir.appendingPathComponent(item.lastPathComponent)
                try? fm.removeItem(at: dst)
                try? fm.copyItem(at: item, to: dst)
            }
        }
        return targetDir
    }

    private func loadBundledTracks(fixturesURL: URL?) -> [[String: Any]] {
        guard let dir = fixturesURL else { return [] }
        let manifestURL = dir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sources = obj["sources"] as? [String: [String: Any]] else {
            return []
        }
        return sources.keys.sorted().map { name in
            let meta = sources[name] ?? [:]
            let filePath = dir.appendingPathComponent(name).path
            return [
                "id": name,
                "title": name,
                "artist": "Fidelune Test Signal",
                "album": (meta["codec"] as? String ?? "fixture").uppercased(),
                "filePath": filePath,
                "fileName": name,
                "isBundledFixture": true,
                "isPrePackagedDopWav": name == "dop64.wav",
                "metadata": meta,
            ]
        }
    }

    private func scanUserMusicTracks() -> [[String: Any]] {
        let fm = FileManager.default
        guard let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return []
        }
        let musicDir = docs.appendingPathComponent("Music", isDirectory: true)
        try? fm.createDirectory(at: musicDir, withIntermediateDirectories: true)

        let allowed = Set(["flac", "wav", "aif", "aiff", "m4a", "alac", "aac", "mp3", "ogg", "opus", "wv", "ape", "dsf", "dff"])
        guard let enumerator = fm.enumerator(at: musicDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var tracks: [[String: Any]] = []
        for case let fileURL as URL in enumerator {
            guard allowed.contains(fileURL.pathExtension.lowercased()) else { continue }
            let name = fileURL.lastPathComponent
            tracks.append([
                "id": fileURL.path,
                "title": fileURL.deletingPathExtension().lastPathComponent,
                "artist": "我的 iPhone · Music",
                "album": fileURL.deletingLastPathComponent().lastPathComponent,
                "filePath": fileURL.path,
                "fileName": name,
                "isBundledFixture": false,
                "isPrePackagedDopWav": false,
            ])
        }
        return tracks.sorted { ($0["fileName"] as? String ?? "") < ($1["fileName"] as? String ?? "") }
    }

    private func acceptanceStateURL() -> URL? {
        guard let docs = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        return docs.appendingPathComponent("fidelune-acceptance-state-v2.json")
    }

    private func writeAcceptanceState(json: String) -> Bool {
        guard let url = acceptanceStateURL() else { return false }
        return (try? json.write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    private func readAcceptanceState() -> String? {
        guard let url = acceptanceStateURL(),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func presentShareSheet(for items: [Any]) {
        DispatchQueue.main.async {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let rootVC = scenes.first?.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scenes.first?.windows.first?.rootViewController else {
                return
            }
            let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let pop = activityVC.popoverPresentationController {
                pop.sourceView = rootVC.view
                pop.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 1, height: 1)
            }
            rootVC.present(activityVC, animated: true)
        }
    }
}

extension AppDelegate: PlaybackQueueCoordinatorListener {
    func coordinatorDidUpdateState(_ payload: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?([
                "type": "state",
                "payload": payload,
            ])
        }
    }

    func coordinatorDidEmitAlert(code: String, message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?([
                "type": "alert",
                "code": code,
                "message": message,
            ])
        }
    }
}

extension AppDelegate: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        events([
            "type": "state",
            "payload": coordinator.statePayload(),
        ])
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
