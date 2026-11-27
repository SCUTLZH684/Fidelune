import Foundation

protocol PlaybackQueueCoordinatorListener: AnyObject {
    func coordinatorDidUpdateState(_ payload: [String: Any])
    func coordinatorDidEmitAlert(code: String, message: String)
}

final class PlaybackQueueCoordinator {
    private enum PersistKey {
        static let queue = "fidelune_bass_saved_queue"
        static let index = "fidelune_bass_saved_index"
        static let position = "fidelune_bass_saved_position"
        static let dsdMode = "fidelune_bass_dsd_mode"
        static let playbackMode = "fidelune_bass_playback_mode"
        static let settings = "fidelune_bass_engine_settings"
    }

    private let backend: AudioPlaybackBackend
    private let sessionManager: DacSessionManager
    private let nowPlaying: NowPlayingAndRemoteController
    private let logger: DiagnosticsSink
    private let defaults: UserDefaults

    weak var listener: PlaybackQueueCoordinatorListener?

    private(set) var queue: [TrackSpec] = []
    private(set) var playOrder: [Int] = []
    private(set) var currentOrderIndex: Int = -1
    private(set) var playbackMode: PlaybackMode = .sequential
    private(set) var dsdMode: DsdOutputMode = .auto
    private(set) var dopSafetyAcknowledged: Bool = false
    private(set) var settings: EngineSettings = EngineSettings()
    private(set) var isPlaying: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var positionSeconds: Double = 0
    private(set) var durationSeconds: Double = 0
    private(set) var signalPath: SignalPathSnapshot = .idle
    private(set) var lastErrorMessage: String?

    private var consecutiveFailureCount = 0
    private var lastPositionPersistTime: Date = .distantPast

    init(
        backend: AudioPlaybackBackend,
        sessionManager: DacSessionManager,
        nowPlaying: NowPlayingAndRemoteController,
        logger: DiagnosticsSink = DiagnosticsLogger.shared,
        defaults: UserDefaults = .standard
    ) {
        self.backend = backend
        self.sessionManager = sessionManager
        self.nowPlaying = nowPlaying
        self.logger = logger
        self.defaults = defaults

        self.backend.delegate = self
        self.sessionManager.delegate = self
        self.nowPlaying.delegate = self

        loadPersistedPreferences()
    }

    func initializeEngine() -> Bool {
        let ok = backend.initialize()
        nowPlaying.registerRemoteCommands()
        emitState()
        return ok
    }

    var currentTrack: TrackSpec? {
        guard currentOrderIndex >= 0 && currentOrderIndex < playOrder.count else { return nil }
        let idx = playOrder[currentOrderIndex]
        guard idx >= 0 && idx < queue.count else { return nil }
        return queue[idx]
    }

    func playQueue(
        tracks: [TrackSpec],
        startIndex: Int = 0,
        startPositionSeconds: Double = 0,
        dsdModeOverride: DsdOutputMode? = nil
    ) {
        guard !tracks.isEmpty else {
            stop(reason: "empty_queue")
            return
        }
        if let dsdModeOverride {
            dsdMode = dsdModeOverride
            defaults.set(dsdMode.rawValue, forKey: PersistKey.dsdMode)
        }

        queue = tracks
        consecutiveFailureCount = 0
        lastErrorMessage = nil
        rebuildPlayOrder(keepingTrackAt: max(0, min(tracks.count - 1, startIndex)), resetIndexToStart: true)
        savePersistedQueue()
        startCurrentTrack(at: startPositionSeconds)
    }

    func play() {
        sessionManager.markUserCommandDuringInterruption()
        sessionManager.markUserStartedPlayback()
        if isPaused {
            backend.resume(fadeMs: settings.pcmFadeMs, completion: nil)
        } else if currentTrack != nil {
            startCurrentTrack(at: positionSeconds)
        }
    }

    func pause() {
        sessionManager.markUserCommandDuringInterruption()
        guard isPlaying else { return }
        backend.pause(fadeMs: settings.pcmFadeMs, completion: nil)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop(reason: String? = nil) {
        sessionManager.markUserCommandDuringInterruption()
        isPlaying = false
        isPaused = false
        positionSeconds = 0
        durationSeconds = 0
        backend.stop(immediate: false, fadeMs: settings.pcmFadeMs, reason: reason, completion: nil)
    }

    func next(manual: Bool = true) {
        if manual {
            sessionManager.markUserCommandDuringInterruption()
            consecutiveFailureCount = 0
        }
        guard !playOrder.isEmpty else { return }
        if currentOrderIndex + 1 < playOrder.count {
            currentOrderIndex += 1
            startCurrentTrack(at: 0)
        } else if playbackMode == .repeatAll || (manual && playbackMode == .sequential) {
            currentOrderIndex = 0
            startCurrentTrack(at: 0)
        } else {
            stop(reason: "queue_finished")
        }
    }

    func previous() {
        sessionManager.markUserCommandDuringInterruption()
        consecutiveFailureCount = 0
        guard !playOrder.isEmpty else { return }
        if positionSeconds > 3.0 {
            seek(to: 0)
            return
        }
        if currentOrderIndex > 0 {
            currentOrderIndex -= 1
        } else {
            currentOrderIndex = playOrder.count - 1
        }
        startCurrentTrack(at: 0)
    }

    func seek(to seconds: Double) {
        sessionManager.markUserCommandDuringInterruption()
        backend.seek(to: seconds, fadeMs: settings.pcmFadeMs, completion: nil)
    }

    func setPlaybackMode(_ mode: PlaybackMode) {
        playbackMode = mode
        defaults.set(mode.rawValue, forKey: PersistKey.playbackMode)
        let activeIdx = (currentOrderIndex >= 0 && currentOrderIndex < playOrder.count) ? playOrder[currentOrderIndex] : 0
        rebuildPlayOrder(keepingTrackAt: activeIdx, resetIndexToStart: false)
        backend.updateQueuedNextTrack(nextTrackForGaplessPreview())
        emitState()
    }

    func setDsdMode(_ mode: DsdOutputMode) {
        dsdMode = mode
        defaults.set(mode.rawValue, forKey: PersistKey.dsdMode)
        emitState()
    }

    func setDopSafetyAcknowledged(_ ack: Bool) {
        dopSafetyAcknowledged = ack
        logger.log(
            event: "dop-safety-acknowledged",
            category: "safety",
            message: "DoP safety checklist acknowledged=\(ack)"
        )
        emitState()
    }

    func updateSettings(_ dict: [String: Any]) {
        settings.update(from: dict)
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: PersistKey.settings)
        }
        sessionManager.applySessionMode(settings.sessionMode)
        emitState()
    }

    func probeDacRate(_ targetHz: Int) -> RateNegotiationResult {
        stop(reason: "dac_rate_probe")
        let result = sessionManager.negotiateSampleRate(
            targetHz: targetHz,
            strategy: settings.rateSwitchStrategy,
            settleDelayMs: settings.dacSettleDelayMs,
            bassReinit: { [weak self] hz in
                self?.backend.reinitializeSampleRate(hz) ?? false
            }
        )
        emitState()
        return result
    }

    func statePayload() -> [String: Any] {
        let trackDict: [String: Any]? = currentTrack.map {
            [
                "id": $0.id,
                "title": $0.title,
                "artist": $0.artist,
                "album": $0.album,
                "filePath": $0.filePath,
                "fileName": $0.fileName,
                "isBundledFixture": $0.isBundledFixture,
                "isPrePackagedDopWav": $0.isPrePackagedDopWav,
            ]
        }
        return [
            "isPlaying": isPlaying,
            "isPaused": isPaused,
            "positionSeconds": positionSeconds,
            "durationSeconds": durationSeconds,
            "currentIndex": currentOrderIndex,
            "queueCount": playOrder.count,
            "playbackMode": playbackMode.rawValue,
            "dsdMode": dsdMode.rawValue,
            "dopSafetyAcknowledged": dopSafetyAcknowledged,
            "currentTrack": trackDict as Any,
            "signalPath": signalPath.toDictionary(),
            "dacProfile": sessionManager.currentProfile().toDictionary(),
            "settings": settings.toDictionary(),
            "lastErrorMessage": lastErrorMessage as Any,
        ]
    }

    // MARK: - Private Queue Logic

    private func startCurrentTrack(at startPosition: Double) {
        guard let track = currentTrack else { return }
        lastErrorMessage = nil
        positionSeconds = startPosition
        let nextCandidate = nextTrackForGaplessPreview()
        backend.startPlayback(
            track: track,
            nextCompatibleTrack: nextCandidate,
            startPositionSeconds: startPosition,
            dsdMode: dsdMode,
            dopSafetyAcknowledged: dopSafetyAcknowledged,
            settings: settings
        )
        savePersistedQueue()
        emitState()
    }

    private func nextTrackForGaplessPreview() -> TrackSpec? {
        guard !playOrder.isEmpty, currentOrderIndex >= 0 else { return nil }
        switch playbackMode {
        case .repeatOne:
            return currentTrack
        case .sequential:
            guard currentOrderIndex + 1 < playOrder.count else { return nil }
            return queue[playOrder[currentOrderIndex + 1]]
        case .repeatAll, .shuffle:
            let nextOrd = (currentOrderIndex + 1) % playOrder.count
            return queue[playOrder[nextOrd]]
        }
    }

    private func rebuildPlayOrder(keepingTrackAt rawIndex: Int, resetIndexToStart: Bool) {
        let count = queue.count
        guard count > 0 else {
            playOrder = []
            currentOrderIndex = -1
            return
        }
        let clampedRaw = max(0, min(count - 1, rawIndex))
        if playbackMode == .shuffle && count > 1 {
            var rest = (0..<count).filter { $0 != clampedRaw }
            rest.shuffle()
            playOrder = [clampedRaw] + rest
            currentOrderIndex = 0
        } else {
            playOrder = Array(0..<count)
            currentOrderIndex = resetIndexToStart ? clampedRaw : (playOrder.firstIndex(of: clampedRaw) ?? 0)
        }
    }

    private func emitState() {
        let payload = statePayload()
        nowPlaying.updateNowPlaying(
            track: currentTrack,
            isPlaying: isPlaying,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            signalPath: signalPath
        )
        listener?.coordinatorDidUpdateState(payload)
    }

    private func savePersistedQueue() {
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: PersistKey.queue)
        }
        defaults.set(currentOrderIndex, forKey: PersistKey.index)
        let savedPos = settings.rememberExactPosition ? positionSeconds : 0.0
        defaults.set(savedPos, forKey: PersistKey.position)
    }

    private func loadPersistedPreferences() {
        if let rawMode = defaults.string(forKey: PersistKey.playbackMode), let mode = PlaybackMode(rawValue: rawMode) {
            playbackMode = mode
        }
        if let rawDsd = defaults.string(forKey: PersistKey.dsdMode), let dsd = DsdOutputMode(rawValue: rawDsd) {
            dsdMode = dsd
        }
        if let data = defaults.data(forKey: PersistKey.settings),
           let decoded = try? JSONDecoder().decode(EngineSettings.self, from: data) {
            settings = decoded
        }
        if let qData = defaults.data(forKey: PersistKey.queue),
           let savedQueue = try? JSONDecoder().decode([TrackSpec].self, from: qData),
           !savedQueue.isEmpty {
            let existing = savedQueue.filter { FileManager.default.fileExists(atPath: $0.filePath) }
            if !existing.isEmpty {
                queue = existing
                let savedIdx = max(0, min(existing.count - 1, defaults.integer(forKey: PersistKey.index)))
                rebuildPlayOrder(keepingTrackAt: savedIdx, resetIndexToStart: true)
                positionSeconds = settings.rememberExactPosition ? max(0, defaults.double(forKey: PersistKey.position)) : 0
            }
        }
    }
}

// MARK: - AudioPlaybackBackendDelegate

extension PlaybackQueueCoordinator: AudioPlaybackBackendDelegate {
    func backendDidStartPlaying(track: TrackSpec, signalPath: SignalPathSnapshot) {
        isPlaying = true
        isPaused = false
        self.signalPath = signalPath
        durationSeconds = backend.currentDurationSeconds
        emitState()
    }

    func backendDidPause(positionSeconds: Double) {
        isPlaying = false
        isPaused = true
        self.positionSeconds = positionSeconds
        savePersistedQueue()
        emitState()
    }

    func backendDidStop(reason: String?) {
        isPlaying = false
        isPaused = false
        positionSeconds = 0
        signalPath = .idle
        emitState()
    }

    func backendDidAdvanceGaplessly(to track: TrackSpec, signalPath: SignalPathSnapshot) {
        if let nextIdx = playOrder.indices.first(where: { $0 > currentOrderIndex && queue[playOrder[$0]].id == track.id }) {
            currentOrderIndex = nextIdx
        } else if currentOrderIndex + 1 < playOrder.count {
            currentOrderIndex += 1
        } else if playbackMode == .repeatAll || playbackMode == .shuffle {
            currentOrderIndex = 0
        }
        isPlaying = true
        isPaused = false
        consecutiveFailureCount = 0
        positionSeconds = 0
        durationSeconds = backend.currentDurationSeconds
        self.signalPath = signalPath
        backend.updateQueuedNextTrack(nextTrackForGaplessPreview())
        savePersistedQueue()
        emitState()
    }

    func backendDidCompleteTrack(track: TrackSpec) {
        if playbackMode == .repeatOne {
            startCurrentTrack(at: 0)
            return
        }
        if currentOrderIndex + 1 < playOrder.count {
            currentOrderIndex += 1
            startCurrentTrack(at: 0)
        } else if playbackMode == .repeatAll || playbackMode == .shuffle {
            if playbackMode == .shuffle && queue.count > 1 {
                rebuildPlayOrder(keepingTrackAt: playOrder[currentOrderIndex], resetIndexToStart: false)
            }
            currentOrderIndex = 0
            startCurrentTrack(at: 0)
        } else {
            isPlaying = false
            isPaused = false
            positionSeconds = 0
            signalPath = .idle
            emitState()
        }
    }

    func backendDidUpdatePosition(seconds: Double, durationSeconds: Double) {
        self.positionSeconds = seconds
        if seconds >= 0.5 {
            consecutiveFailureCount = 0
        }
        if durationSeconds > 0 {
            self.durationSeconds = durationSeconds
        }
        if settings.rememberExactPosition && Date().timeIntervalSince(lastPositionPersistTime) > 5.0 {
            lastPositionPersistTime = Date()
            defaults.set(seconds, forKey: PersistKey.position)
        }
        emitState()
    }

    func backendDidUpdateSignalPath(_ signalPath: SignalPathSnapshot) {
        self.signalPath = signalPath
        emitState()
    }

    func backendDidFailTrack(track: TrackSpec, code: String, message: String) {
        lastErrorMessage = message
        logger.log(
            event: "track-failed",
            category: "playback",
            message: "\(track.fileName) failed [\(code)]: \(message)",
            fields: ["fileName": track.fileName, "code": code]
        )
        listener?.coordinatorDidEmitAlert(code: code, message: message)

        // DoP safety failure must halt immediately instead of auto-advancing into noise.
        if code.hasPrefix("dop_") {
            isPlaying = false
            isPaused = false
            emitState()
            return
        }

        consecutiveFailureCount += 1
        if consecutiveFailureCount >= max(1, queue.count) {
            isPlaying = false
            isPaused = false
            let haltMsg = "连续 \(consecutiveFailureCount) 个文件无法播放，已自动停止以防止死循环重试。最后错误：\(message)"
            lastErrorMessage = haltMsg
            listener?.coordinatorDidEmitAlert(code: "consecutive_failures", message: haltMsg)
            emitState()
            return
        }

        if currentOrderIndex + 1 < playOrder.count || playbackMode == .repeatAll {
            next(manual: false)
        } else {
            isPlaying = false
            isPaused = false
            emitState()
        }
    }
}

// MARK: - DacSessionManagerDelegate

extension PlaybackQueueCoordinator: DacSessionManagerDelegate {
    func sessionDidUpdateProfile(_ profile: DacCapabilityProfile) {
        emitState()
    }

    func sessionDidRequestPauseForRouteRemoval(route: OutputRouteKind) {
        if isPlaying {
            backend.pause(fadeMs: 0, completion: nil)
            listener?.coordinatorDidEmitAlert(
                code: "route_removed_paused",
                message: "输出设备已断开，已自动安全暂停（当前路由：\(route.displayLabel)）以防意外外放。"
            )
        } else {
            emitState()
        }
    }

    func sessionDidObserveRouteArrival(profile: DacCapabilityProfile) {
        emitState()
    }

    func sessionDidBeginInterruption(wasPlaying: Bool) {
        if wasPlaying {
            backend.pause(fadeMs: settings.pcmFadeMs, completion: nil)
        }
        emitState()
    }

    func sessionShouldResumeAfterInterruption() {
        guard isPaused, currentTrack != nil else { return }
        backend.resume(fadeMs: settings.pcmFadeMs, completion: nil)
    }

    func sessionDidObserveMediaServicesLost() {
        backend.emergencySafetyHalt(reason: "media_services_lost")
        listener?.coordinatorDidEmitAlert(code: "media_services_lost", message: "iOS 媒体服务中断，正在等待系统恢复。")
    }

    func sessionDidObserveMediaServicesReset() {
        if backend.reinitializeDeviceAfterMediaReset() {
            listener?.coordinatorDidEmitAlert(code: "media_services_reset", message: "iOS 媒体服务已重置并重新初始化 BASS。")
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                _ = self?.backend.reinitializeDeviceAfterMediaReset()
            }
        }
        emitState()
    }

    func sessionDidTriggerDopSafetyViolation(reason: DopSafetyFailure) {
        backend.emergencySafetyHalt(reason: reason.code)
        listener?.coordinatorDidEmitAlert(code: reason.code, message: reason.message)
        emitState()
    }
}

// MARK: - RemoteCommandDelegate

extension PlaybackQueueCoordinator: RemoteCommandDelegate {
    func remoteDidRequestPlay() { play() }
    func remoteDidRequestPause() { pause() }
    func remoteDidRequestToggle() { togglePlayPause() }
    func remoteDidRequestNext() { next(manual: true) }
    func remoteDidRequestPrevious() { previous() }
    func remoteDidRequestSeek(seconds: Double) { seek(to: seconds) }
}
