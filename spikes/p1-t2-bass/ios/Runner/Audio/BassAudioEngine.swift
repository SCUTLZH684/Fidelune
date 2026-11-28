import Foundation

enum BassPluginRegistry {
    private static let lock = NSLock()
    private static var loadedHandles: [String: HPLUGIN] = [:]

    private static let pluginSpecs: [(index: Int32, name: String)] = [
        (0, "bassflac"),
        (1, "bassdsd"),
        (2, "basswv"),
        (3, "bassape"),
        (4, "bassopus"),
    ]

    static func ensureAllPluginsLoaded(
        logger: DiagnosticsSink? = nil
    ) -> (loaded: [String: HPLUGIN], missing: [String], errors: [String: Int32]) {
        lock.lock()
        defer { lock.unlock() }

        var missing: [String] = []
        var errors: [String: Int32] = [:]

        for spec in pluginSpecs {
            if let existing = loadedHandles[spec.name], existing != 0 {
                continue
            }

            var handle: HPLUGIN = 0
            var lastErr: Int32 = 0

            func tryLoad(_ block: () -> HPLUGIN) -> Bool {
                let h = block()
                if h != 0 {
                    handle = h
                    return true
                }
                let code = BASS_ErrorGetCode()
                if code == BASS_ERROR_ALREADY {
                    handle = 1
                    return true
                }
                lastErr = code
                return false
            }

            let ok =
                tryLoad { FideluneLoadPluginByIndex(spec.index) } ||
                tryLoad { spec.name.withCString { BASS_PluginLoad($0, 0) } } ||
                tryLoad { "@rpath/\(spec.name).framework/\(spec.name)".withCString { BASS_PluginLoad($0, 0) } } ||
                [
                    Bundle.main.privateFrameworksURL?.appendingPathComponent("\(spec.name).framework/\(spec.name)").path,
                    Bundle(for: BassAudioEngine.self).privateFrameworksURL?.appendingPathComponent("\(spec.name).framework/\(spec.name)").path,
                ].compactMap { $0 }.contains { path in
                    tryLoad { path.withCString { BASS_PluginLoad($0, 0) } }
                }

            if ok && handle != 0 {
                loadedHandles[spec.name] = handle
            } else {
                missing.append(spec.name)
                errors[spec.name] = lastErr
                logger?.log(
                    event: "bass-plugin-load-failed",
                    category: "engine",
                    message: "Failed to load plugin \(spec.name): BASS error \(lastErr)",
                    fields: ["plugin": spec.name, "bassError": lastErr]
                )
            }
        }

        return (loadedHandles, missing, errors)
    }
}

final class BassAudioEngine: AudioPlaybackBackend {
    weak var delegate: AudioPlaybackBackendDelegate?

    private let sessionManager: DacSessionManager
    private let logger: DiagnosticsSink
    private let engineQueue = DispatchQueue(
        label: "io.github.scutlzh684.fidelune.bass.engine",
        qos: .userInitiated
    )

    private var initialized = false
    private var loadedPlugins: [String: HPLUGIN] = [:]
    private var idlePauseWorkItem: DispatchWorkItem?
    private var progressTimer: DispatchSourceTimer?
    private var dopWatchdogTimer: DispatchSourceTimer?
    private var norampRestoreWorkItem: DispatchWorkItem?
    private var pendingOperationWorkItem: DispatchWorkItem?
    private var operationEpoch: Int = 0
    private var lastRateRecoveryAttempt: Date = .distantPast

    // Active PCM mixer state (guarded by engineQueue)
    private var mixerStream: HSTREAM = 0
    private var activeSource: HSTREAM = 0
    private var queuedNextSource: HSTREAM = 0
    private var activeTrack: TrackSpec?
    private var activeFormat: AudioFormatSignature?
    private var queuedNextTrack: TrackSpec?
    private var queuedNextFormat: AudioFormatSignature?

    // Active DoP stream state (guarded by engineQueue)
    private var dopStream: DopPassthroughStream?

    private var isPausedState = false
    private var isPlayingState = false
    private var cachedPositionSeconds: Double = 0
    private var cachedDurationSeconds: Double = 0
    private var lastSettings = EngineSettings()
    private var lastSignalPath: SignalPathSnapshot = .idle

    var isPlaying: Bool {
        engineQueue.sync { isPlayingState && !isPausedState }
    }

    var currentPositionSeconds: Double {
        engineQueue.sync { computePositionLocked() }
    }

    var currentDurationSeconds: Double {
        engineQueue.sync { cachedDurationSeconds }
    }

    var currentBassDeviceRateHz: Int {
        var info = BASS_INFO()
        return BASS_GetInfo(&info) != 0 ? Int(info.freq) : 0
    }

    var currentSignalPath: SignalPathSnapshot {
        engineQueue.sync { lastSignalPath }
    }

    init(sessionManager: DacSessionManager, logger: DiagnosticsSink = DiagnosticsLogger.shared) {
        self.sessionManager = sessionManager
        self.logger = logger
    }

    deinit {
        progressTimer?.cancel()
        dopWatchdogTimer?.cancel()
        idlePauseWorkItem?.cancel()
        norampRestoreWorkItem?.cancel()
        pendingOperationWorkItem?.cancel()
    }

    func initialize() -> Bool {
        engineQueue.sync {
            if initialized { return true }
            // LyrPlay / BASS iOS pattern: disable BASS_IOS_SESSION_MIX & BTHFP BEFORE BASS_Init
            // so Lock Screen / Dynamic Island controls stay eligible and USB DAC clock isn't shared.
            BASS_SetConfig(DWORD(BASS_CONFIG_IOS_SESSION), 0)
            sessionManager.activateAtStartup(modeOption: lastSettings.sessionMode)

            var code = initBassDeviceLocked(targetHz: 48000, reinit: false)
            #if targetEnvironment(simulator)
            if code != BASS_OK && code != BASS_ERROR_ALREADY {
                // Headless CI macOS runners may expose no default CoreAudio device to iOS Simulator;
                // fall back to BASS "No sound" device (0) only on Simulator so decoding/mixer checks run.
                let noSoundCode = initBassNoSoundSimulatorLocked(targetHz: 48000)
                if noSoundCode == BASS_OK || noSoundCode == BASS_ERROR_ALREADY {
                    code = noSoundCode
                }
            }
            #endif
            guard code == BASS_OK || code == BASS_ERROR_ALREADY else {
                logger.log(
                    event: "bass-init-failed",
                    category: "engine",
                    message: "BASS_Init failed with error \(code)",
                    fields: ["bassError": code]
                )
                return false
            }

            // Re-assert exclusive playback session after BASS_Init in case iOS touched options
            _ = sessionManager.configurePlaybackSession(modeOption: lastSettings.sessionMode)

            // Load official format plugins cleanly
            let pluginState = BassPluginRegistry.ensureAllPluginsLoaded(logger: logger)
            loadedPlugins = pluginState.loaded

            BASS_SetConfig(DWORD(BASS_CONFIG_FLOAT), 1)
            BASS_SetConfig(DWORD(BASS_CONFIG_FLOATDSP), 1)
            BASS_SetConfig(DWORD(BASS_CONFIG_DEV_NONSTOP), 1)
            BASS_SetConfig(DWORD(BASS_CONFIG_GVOL_STREAM), 10000)
            BASS_SetConfig(DWORD(BASS_CONFIG_NET_META), 0)
            BASS_SetConfig(DWORD(BASS_CONFIG_BUFFER), 250)
            BASS_SetConfig(DWORD(BASS_CONFIG_UPDATEPERIOD), 20)

            initialized = true
            startProgressTimerLocked()
            logger.log(
                event: "bass-initialized",
                category: "engine",
                message: "BASS \(String(format: "0x%08X", BASS_GetVersion())) initialized with plugins \(Array(loadedPlugins.keys).sorted())",
                fields: [
                    "bassVersion": String(format: "0x%08X", BASS_GetVersion()),
                    "bassMixVersion": String(format: "0x%08X", BASS_Mixer_GetVersion()),
                    "plugins": Array(loadedPlugins.keys).sorted(),
                    "missingPlugins": pluginState.missing,
                    "initCode": code,
                    "deviceRateHz": currentBassDeviceRateHz,
                ]
            )
            return true
        }
    }

    func reinitializeDeviceAfterMediaReset() -> Bool {
        engineQueue.sync {
            teardownStreamsLocked(stopDevice: false)
            if BASS_Free() == 0 {
                let err = BASS_ErrorGetCode()
                if err == BASS_ERROR_BUSY {
                    return false
                }
            }
            BASS_SetConfig(DWORD(BASS_CONFIG_IOS_SESSION), 0)
            sessionManager.activateAtStartup(modeOption: lastSettings.sessionMode)
            var code = initBassDeviceLocked(targetHz: max(44100, sessionManager.lastRequestedSampleRateHz), reinit: false)
            if code == BASS_ERROR_ALREADY {
                _ = BASS_Free()
                code = initBassDeviceLocked(targetHz: max(44100, sessionManager.lastRequestedSampleRateHz), reinit: false)
            }
            _ = sessionManager.configurePlaybackSession(modeOption: lastSettings.sessionMode)
            initialized = (code == BASS_OK)
            return initialized
        }
    }

    func reinitializeSampleRate(_ targetHz: Int) -> Bool {
        engineQueue.sync {
            reinitBassDeviceSampleRateLocked(targetHz)
        }
    }

    func startPlayback(
        track: TrackSpec,
        nextCompatibleTrack: TrackSpec?,
        startPositionSeconds: Double,
        dsdMode: DsdOutputMode,
        dopSafetyAcknowledged: Bool,
        settings: EngineSettings
    ) {
        engineQueue.async { [weak self] in
            guard let self else { return }
            self.lastSettings = settings
            self.sessionManager.applySessionMode(settings.sessionMode)
            self.sessionManager.markUserStartedPlayback()
            self.cancelIdlePauseLocked()
            self.operationEpoch += 1
            let epoch = self.operationEpoch
            self.pendingOperationWorkItem?.cancel()

            let transitionOutNeeded = self.isPlayingState && !self.isPausedState
            if transitionOutNeeded {
                self.fadeOutAndTeardownLocked(fadeMs: settings.pcmFadeMs, dopTrailMs: settings.dopSilenceTrailMs) { [weak self] in
                    guard let self, self.operationEpoch == epoch else { return }
                    self.openAndStartTrackLocked(
                        track: track,
                        nextTrack: nextCompatibleTrack,
                        startPositionSeconds: startPositionSeconds,
                        dsdMode: dsdMode,
                        dopSafetyAcknowledged: dopSafetyAcknowledged,
                        settings: settings
                    )
                }
            } else {
                self.teardownStreamsLocked(stopDevice: false)
                self.openAndStartTrackLocked(
                    track: track,
                    nextTrack: nextCompatibleTrack,
                    startPositionSeconds: startPositionSeconds,
                    dsdMode: dsdMode,
                    dopSafetyAcknowledged: dopSafetyAcknowledged,
                    settings: settings
                )
            }
        }
    }

    func updateQueuedNextTrack(_ nextTrack: TrackSpec?) {
        engineQueue.async { [weak self] in
            guard let self, self.mixerStream != 0, self.dopStream == nil, let activeSig = self.activeFormat else {
                return
            }
            if self.queuedNextSource != 0 {
                let existingQueued = self.queuedNextSource
                BASS_Mixer_ChannelRemove(existingQueued)
                BASS_StreamFree(existingQueued)
                self.queuedNextSource = 0
                self.queuedNextTrack = nil
                self.queuedNextFormat = nil
            }
            if let nextTrack {
                self.tryQueueCompatibleTrackLocked(nextTrack: nextTrack, activeSignature: activeSig)
            }
            self.refreshSignalPathLocked()
        }
    }

    func pause(fadeMs: Int, completion: (() -> Void)?) {
        engineQueue.async { [weak self] in
            guard let self else {
                completion?()
                return
            }
            guard self.isPlayingState && !self.isPausedState else {
                completion?()
                return
            }
            self.operationEpoch += 1
            let epoch = self.operationEpoch
            self.cancelDopWatchdogLocked()
            self.norampRestoreWorkItem?.cancel()

            if let dop = self.dopStream {
                dop.beginTrailSilenceAndStop(trailMs: self.lastSettings.dopSilenceTrailMs) { [weak self] in
                    guard let self else { return }
                    self.engineQueue.async {
                        guard self.operationEpoch == epoch else {
                            completion?()
                            return
                        }
                        BASS_ChannelPause(dop.outputHandle)
                        self.isPausedState = true
                        self.isPlayingState = false
                        self.cachedPositionSeconds = dop.currentPositionSeconds()
                        self.sessionManager.setActiveStreamExpectation(isDop: false, expectedRateHz: nil)
                        self.scheduleIdlePauseLocked()
                        let pos = self.cachedPositionSeconds
                        DispatchQueue.main.async {
                            self.delegate?.backendDidPause(positionSeconds: pos)
                            completion?()
                        }
                    }
                }
                return
            }

            guard self.mixerStream != 0 else {
                completion?()
                return
            }
            self.rampDownAndDrainPcmLocked(stream: self.mixerStream, fadeMs: max(16, fadeMs))
            self.cachedPositionSeconds = self.computePositionLocked()
            BASS_ChannelPause(self.mixerStream)
            self.isPausedState = true
            self.isPlayingState = false
            self.sessionManager.setActiveStreamExpectation(isDop: false, expectedRateHz: nil)
            self.scheduleIdlePauseLocked()
            let pos = self.cachedPositionSeconds
            self.refreshSignalPathLocked()
            DispatchQueue.main.async {
                self.delegate?.backendDidPause(positionSeconds: pos)
                completion?()
            }
        }
    }

    func resume(fadeMs: Int, completion: (() -> Void)?) {
        engineQueue.async { [weak self] in
            guard let self else {
                completion?()
                return
            }
            self.cancelIdlePauseLocked()
            self.norampRestoreWorkItem?.cancel()
            self.sessionManager.reactivateSession(modeOption: self.lastSettings.sessionMode)
            self.operationEpoch += 1
            if BASS_IsStarted() == 0 {
                _ = BASS_Start()
            }

            if let dop = self.dopStream {
                if case .failure(let safetyFailure) = self.sessionManager.validateDopSafety(
                    carrierHz: dop.carrierRateHz,
                    userAcknowledged: true
                ) {
                    self.teardownStreamsLocked(stopDevice: false)
                    self.isPlayingState = false
                    self.isPausedState = false
                    DispatchQueue.main.async {
                        if let track = self.activeTrack {
                            self.delegate?.backendDidFailTrack(
                                track: track,
                                code: safetyFailure.code,
                                message: safetyFailure.message
                            )
                        }
                        completion?()
                    }
                    return
                }
                let targetCarrier = dop.carrierRateHz
                let neg = self.sessionManager.negotiateSampleRate(
                    targetHz: targetCarrier,
                    strategy: self.lastSettings.rateSwitchStrategy,
                    settleDelayMs: self.lastSettings.dacSettleDelayMs,
                    sessionModeOption: self.lastSettings.sessionMode,
                    bassReinit: { [weak self] hz in self?.reinitBassDeviceSampleRateLocked(hz) ?? false }
                )
                guard neg.matchedTarget else {
                    self.teardownStreamsLocked(stopDevice: false)
                    self.isPlayingState = false
                    self.isPausedState = false
                    DispatchQueue.main.async {
                        if let track = self.activeTrack {
                            self.delegate?.backendDidFailTrack(
                                track: track,
                                code: "dop_resume_rate_mismatch",
                                message: "恢复 DoP 失败：设备采样率未能锁回 \(targetCarrier) Hz（当前会话 \(neg.sessionActualHz) Hz）。"
                            )
                        }
                        completion?()
                    }
                    return
                }
                dop.prepareResumeLeadSilence(ms: self.lastSettings.dopSilenceLeadMs)
                BASS_SetConfig(DWORD(BASS_CONFIG_GVOL_STREAM), 10000)
                BASS_ChannelSetAttribute(dop.outputHandle, DWORD(BASS_ATTRIB_VOL), 1.0)
                // restart=1 clears BASS_STREAMPROC_END from pause trail silence while continuing from decoderHandle's paused offset.
                if BASS_ChannelPlay(dop.outputHandle, 1) != 0 {
                    self.isPausedState = false
                    self.isPlayingState = true
                    self.sessionManager.setActiveStreamExpectation(isDop: true, expectedRateHz: dop.carrierRateHz)
                    self.startDopWatchdogLocked(carrierHz: dop.carrierRateHz, dopHandle: dop.outputHandle)
                    self.refreshSignalPathLocked()
                    let sig = self.lastSignalPath
                    if let track = self.activeTrack {
                        DispatchQueue.main.async {
                            self.delegate?.backendDidStartPlaying(track: track, signalPath: sig)
                            completion?()
                        }
                    } else {
                        completion?()
                    }
                } else {
                    completion?()
                }
                return
            }

            guard self.mixerStream != 0 else {
                completion?()
                return
            }
            if let sig = self.activeFormat {
                let targetHz = sig.sampleRateHz
                _ = self.sessionManager.negotiateSampleRate(
                    targetHz: targetHz,
                    strategy: self.lastSettings.rateSwitchStrategy,
                    settleDelayMs: self.lastSettings.dacSettleDelayMs,
                    sessionModeOption: self.lastSettings.sessionMode,
                    bassReinit: { [weak self] hz in self?.reinitBassDeviceSampleRateLocked(hz) ?? false }
                )
            }
            let clampedFade = max(16, fadeMs)
            BASS_ChannelSetAttribute(self.mixerStream, DWORD(BASS_ATTRIB_NORAMP), 0.0)
            BASS_ChannelSetAttribute(self.mixerStream, DWORD(BASS_ATTRIB_VOL), 0.0)
            if BASS_ChannelPlay(self.mixerStream, 0) != 0 {
                BASS_ChannelSlideAttribute(self.mixerStream, DWORD(BASS_ATTRIB_VOL), 1.0, DWORD(clampedFade))
                self.scheduleRestoreNorampLocked(afterMs: clampedFade + 25)
                self.isPausedState = false
                self.isPlayingState = true
                if let fmt = self.activeFormat {
                    self.sessionManager.setActiveStreamExpectation(isDop: false, expectedRateHz: fmt.sampleRateHz)
                }
                self.refreshSignalPathLocked()
                let sigSnap = self.lastSignalPath
                if let track = self.activeTrack {
                    DispatchQueue.main.async {
                        self.delegate?.backendDidStartPlaying(track: track, signalPath: sigSnap)
                        completion?()
                    }
                } else {
                    completion?()
                }
            } else {
                completion?()
            }
        }
    }

    func stop(immediate: Bool, fadeMs: Int, reason: String?, completion: (() -> Void)?) {
        engineQueue.async { [weak self] in
            guard let self else {
                completion?()
                return
            }
            self.cancelIdlePauseLocked()
            self.operationEpoch += 1
            let epoch = self.operationEpoch
            if !immediate && self.isPlayingState && !self.isPausedState {
                self.fadeOutAndTeardownLocked(fadeMs: fadeMs, dopTrailMs: self.lastSettings.dopSilenceTrailMs) { [weak self] in
                    guard let self, self.operationEpoch == epoch else {
                        completion?()
                        return
                    }
                    self.finalizeStopLocked(reason: reason, completion: completion)
                }
            } else {
                self.teardownStreamsLocked(stopDevice: false)
                self.finalizeStopLocked(reason: reason, completion: completion)
            }
        }
    }

    func seek(to seconds: Double, fadeMs: Int, completion: (() -> Void)?) {
        engineQueue.async { [weak self] in
            guard let self else {
                completion?()
                return
            }
            self.operationEpoch += 1
            let epoch = self.operationEpoch
            let clampedTarget = max(0, min(self.cachedDurationSeconds > 0 ? self.cachedDurationSeconds : seconds, seconds))

            if let dop = self.dopStream {
                let wasPlaying = self.isPlayingState && !self.isPausedState
                if wasPlaying {
                    dop.beginTrailSilenceAndStop(trailMs: self.lastSettings.dopSilenceTrailMs) { [weak self] in
                        guard let self else { return }
                        self.engineQueue.async {
                            guard self.operationEpoch == epoch, let currentDop = self.dopStream else {
                                completion?()
                                return
                            }
                            _ = currentDop.seek(to: clampedTarget, leadSilenceMs: self.lastSettings.dopSilenceLeadMs)
                            _ = BASS_Start()
                            _ = BASS_ChannelPlay(currentDop.outputHandle, 1)
                            self.cachedPositionSeconds = clampedTarget
                            DispatchQueue.main.async {
                                self.delegate?.backendDidUpdatePosition(seconds: clampedTarget, durationSeconds: self.cachedDurationSeconds)
                                completion?()
                            }
                        }
                    }
                } else {
                    _ = dop.seek(to: clampedTarget, leadSilenceMs: self.lastSettings.dopSilenceLeadMs)
                    self.cachedPositionSeconds = clampedTarget
                    DispatchQueue.main.async {
                        self.delegate?.backendDidUpdatePosition(seconds: clampedTarget, durationSeconds: self.cachedDurationSeconds)
                        completion?()
                    }
                }
                return
            }

            guard self.mixerStream != 0, self.activeSource != 0 else {
                completion?()
                return
            }

            self.norampRestoreWorkItem?.cancel()
            let wasPlaying = self.isPlayingState && !self.isPausedState
            if wasPlaying {
                self.rampDownAndDrainPcmLocked(stream: self.mixerStream, fadeMs: max(16, fadeMs))
            }

            guard self.operationEpoch == epoch,
                  self.mixerStream != 0, self.activeSource != 0 else {
                completion?()
                return
            }

            let targetBytes = BASS_ChannelSeconds2Bytes(self.activeSource, clampedTarget)
            if targetBytes != UInt64.max {
                if wasPlaying {
                    BASS_ChannelPause(self.mixerStream)
                }
                BASS_Mixer_ChannelSetPosition(
                    self.activeSource,
                    targetBytes,
                    DWORD(BASS_POS_BYTE | BASS_POS_MIXER_RESET)
                )
                // If seeking backwards from very near EOF, queuedNextSource may have already started feeding
                // the mixer buffer; refresh it cleanly so the gapless intro is never truncated.
                if let nextT = self.queuedNextTrack, let activeSig = self.activeFormat {
                    if self.queuedNextSource != 0,
                       BASS_Mixer_ChannelGetPosition(self.queuedNextSource, DWORD(BASS_POS_BYTE)) > 0 {
                        let oldNext = self.queuedNextSource
                        BASS_Mixer_ChannelRemove(oldNext)
                        BASS_StreamFree(oldNext)
                        self.queuedNextSource = 0
                        self.queuedNextFormat = nil
                        self.tryQueueCompatibleTrackLocked(nextTrack: nextT, activeSignature: activeSig)
                    } else if self.queuedNextSource == 0 {
                        self.tryQueueCompatibleTrackLocked(nextTrack: nextT, activeSignature: activeSig)
                    }
                }
                if wasPlaying {
                    let rampMs = max(16, fadeMs)
                    BASS_ChannelSetAttribute(self.mixerStream, DWORD(BASS_ATTRIB_NORAMP), 0.0)
                    // Set VOL = 0.0 BEFORE BASS_ChannelPlay so zero full-scale frames leak past reset!
                    BASS_ChannelSetAttribute(self.mixerStream, DWORD(BASS_ATTRIB_VOL), 0.0)
                    BASS_ChannelPlay(self.mixerStream, 1)
                    BASS_ChannelSlideAttribute(self.mixerStream, DWORD(BASS_ATTRIB_VOL), 1.0, DWORD(rampMs))
                    self.scheduleRestoreNorampLocked(afterMs: rampMs + 25)
                } else {
                    BASS_ChannelSetAttribute(self.mixerStream, DWORD(BASS_ATTRIB_VOL), 1.0)
                    BASS_ChannelSetAttribute(
                        self.mixerStream,
                        DWORD(BASS_ATTRIB_NORAMP),
                        self.lastSettings.strictBitPerfectNoRampIn ? 2.0 : 0.0
                    )
                }
                self.cachedPositionSeconds = clampedTarget
                let dur = self.cachedDurationSeconds
                DispatchQueue.main.async {
                    self.delegate?.backendDidUpdatePosition(seconds: clampedTarget, durationSeconds: dur)
                    completion?()
                }
            } else {
                completion?()
            }
        }
    }

    func emergencySafetyHalt(reason: String) {
        engineQueue.async { [weak self] in
            self?.emergencySafetyHaltLocked(reason: reason)
        }
    }

    func recoverUnexpectedUsbRateDrop(expectedHz: Int) {
        engineQueue.async { [weak self] in
            guard let self else { return }
            guard self.dopStream == nil,
                  self.isPlayingState && !self.isPausedState,
                  self.mixerStream != 0,
                  self.activeSource != 0,
                  let fmt = self.activeFormat,
                  fmt.sampleRateHz == expectedHz else {
                return
            }
            let now = Date()
            guard now.timeIntervalSince(self.lastRateRecoveryAttempt) >= 2.0 else {
                return
            }
            self.lastRateRecoveryAttempt = now

            let profile = self.sessionManager.currentProfile()
            guard profile.routeKind == .usbAudio,
                  (profile.currentSessionSampleRateHz != expectedHz ||
                   (profile.bassDeviceSampleRateHz > 0 && profile.bassDeviceSampleRateHz != expectedHz)) else {
                return
            }

            let savedPos = self.computePositionLocked()
            self.rampDownAndDrainPcmLocked(stream: self.mixerStream, fadeMs: 12)
            BASS_ChannelPause(self.mixerStream)

            let neg = self.sessionManager.negotiateSampleRate(
                targetHz: expectedHz,
                strategy: self.lastSettings.rateSwitchStrategy,
                settleDelayMs: self.lastSettings.dacSettleDelayMs,
                sessionModeOption: self.lastSettings.sessionMode,
                bassReinit: { [weak self] hz in self?.reinitBassDeviceSampleRateLocked(hz) ?? false }
            )

            self.logger.log(
                event: "dac-unexpected-rate-recovery",
                category: "dac",
                message: "USB rate drop recovery to \(expectedHz) Hz -> matched=\(neg.matchedTarget) (session=\(neg.sessionActualHz), BASS=\(neg.bassDeviceHz))",
                fields: neg.toDictionary()
            )

            let resumeBytes = BASS_ChannelSeconds2Bytes(self.activeSource, max(0, savedPos))
            if resumeBytes != UInt64.max {
                BASS_Mixer_ChannelSetPosition(self.activeSource, resumeBytes, DWORD(BASS_POS_BYTE | BASS_POS_MIXER_RESET))
            }
            BASS_ChannelSetAttribute(self.mixerStream, DWORD(BASS_ATTRIB_NORAMP), 0.0)
            BASS_ChannelSetAttribute(self.mixerStream, DWORD(BASS_ATTRIB_VOL), 0.0)
            if BASS_ChannelPlay(self.mixerStream, 1) != 0 {
                let rampMs = max(16, self.lastSettings.pcmFadeMs)
                BASS_ChannelSlideAttribute(self.mixerStream, DWORD(BASS_ATTRIB_VOL), 1.0, DWORD(rampMs))
                self.scheduleRestoreNorampLocked(afterMs: rampMs + 25)
            }
            self.refreshSignalPathLocked()
        }
    }

    // MARK: - Private Engine Internals (Called on engineQueue)

    private func emergencySafetyHaltLocked(reason: String) {
        operationEpoch += 1
        pendingOperationWorkItem?.cancel()
        cancelDopWatchdogLocked()
        norampRestoreWorkItem?.cancel()
        teardownStreamsLocked(stopDevice: true)
        isPlayingState = false
        isPausedState = false
        sessionManager.setActiveStreamExpectation(isDop: false, expectedRateHz: nil)
        lastSignalPath = .idle
        logger.log(
            event: "emergency-safety-halt",
            category: "safety",
            message: "Emergency audio halt triggered: \(reason)"
        )
        DispatchQueue.main.async {
            self.delegate?.backendDidStop(reason: reason)
            self.delegate?.backendDidUpdateSignalPath(.idle)
        }
    }

    private func initBassDeviceLocked(targetHz: Int, reinit: Bool) -> Int32 {
        let device: Int32
        var flags = DWORD(BASS_DEVICE_FREQ)
        if reinit {
            let currentDev = BASS_GetDevice()
            guard currentDev != 0 && currentDev != DWORD.max else {
                return BASS_ERROR_NOTAVAIL
            }
            device = Int32(currentDev)
            flags |= DWORD(BASS_DEVICE_REINIT)
        } else {
            device = -1
        }
        let ok = BASS_Init(device, DWORD(targetHz), flags, nil, nil)
        return ok != 0 ? BASS_OK : BASS_ErrorGetCode()
    }

    #if targetEnvironment(simulator)
    private func initBassNoSoundSimulatorLocked(targetHz: Int) -> Int32 {
        let ok = BASS_Init(0, DWORD(targetHz), DWORD(BASS_DEVICE_FREQ), nil, nil)
        return ok != 0 ? BASS_OK : BASS_ErrorGetCode()
    }
    #endif

    private func reinitBassDeviceSampleRateLocked(_ targetHz: Int) -> Bool {
        let currentDev = BASS_GetDevice()
        let deviceToInit: Int32 = (currentDev != 0 && currentDev != DWORD.max) ? Int32(currentDev) : 1
        BASS_SetConfig(DWORD(BASS_CONFIG_IOS_SESSION), 0)
        let ok = BASS_Init(
            deviceToInit,
            DWORD(targetHz),
            DWORD(BASS_DEVICE_FREQ | BASS_DEVICE_REINIT),
            nil,
            nil
        )
        if ok == 0 {
            let err = BASS_ErrorGetCode()
            logger.log(
                event: "bass-reinit-rate-failed",
                category: "dac",
                message: "BASS_DEVICE_REINIT to \(targetHz) Hz failed: BASS error \(err)",
                fields: ["targetHz": targetHz, "bassError": err, "device": deviceToInit]
            )
            return false
        }
        _ = sessionManager.configurePlaybackSession(modeOption: lastSettings.sessionMode)
        _ = sessionManager.setPreferredSampleRateDirect(targetHz)
        if BASS_IsStarted() == 0 {
            _ = BASS_Start()
        }
        return true
    }

    private func loadPluginLocked(name: String) -> HPLUGIN {
        let state = BassPluginRegistry.ensureAllPluginsLoaded(logger: logger)
        loadedPlugins = state.loaded
        return state.loaded[name] ?? 0
    }

    private func openAndStartTrackLocked(
        track: TrackSpec,
        nextTrack: TrackSpec?,
        startPositionSeconds: Double,
        dsdMode: DsdOutputMode,
        dopSafetyAcknowledged: Bool,
        settings: EngineSettings
    ) {
        if !initialized {
            _ = initialize()
        }

        // Ensure exclusive AVAudioSession and active output device BEFORE rate negotiation
        _ = sessionManager.configurePlaybackSession(modeOption: settings.sessionMode)
        if BASS_IsStarted() == 0 {
            _ = BASS_Start()
        }

        guard let probed = probeFileFormatLocked(track: track, dsdMode: dsdMode, settings: settings) else {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.backendDidFailTrack(
                    track: track,
                    code: "decode_open_failed",
                    message: "无法解码文件 \(track.fileName)（损坏、不受支持或权限不可读）。"
                )
            }
            return
        }

        let wantDop: Bool
        let targetDeviceRateHz: Int
        if probed.isDsd || track.isPrePackagedDopWav {
            let carrierHz = AudioFormatSignature.dopCarrierHz(forDsdRate: probed.dsdRateHz > 0 ? probed.dsdRateHz : probed.sampleRateHz * 16)
            switch dsdMode {
            case .pcm:
                wantDop = false
                targetDeviceRateHz = resolvePcmTargetRateForCurrentRoute(preferred: settings.dsdPcmTargetRateHz)
            case .auto:
                if case .success = sessionManager.validateDopSafety(carrierHz: carrierHz, userAcknowledged: dopSafetyAcknowledged) {
                    wantDop = true
                    targetDeviceRateHz = carrierHz
                } else {
                    wantDop = false
                    targetDeviceRateHz = resolvePcmTargetRateForCurrentRoute(preferred: settings.dsdPcmTargetRateHz)
                }
            case .dop:
                switch sessionManager.validateDopSafety(carrierHz: carrierHz, userAcknowledged: dopSafetyAcknowledged) {
                case .success:
                    wantDop = true
                    targetDeviceRateHz = carrierHz
                case .failure(let safetyFailure):
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.backendDidFailTrack(
                            track: track,
                            code: safetyFailure.code,
                            message: safetyFailure.message
                        )
                    }
                    return
                }
            }
        } else {
            wantDop = false
            targetDeviceRateHz = probed.sampleRateHz
        }

        // Negotiate hardware sample rate on active output route
        let neg = sessionManager.negotiateSampleRate(
            targetHz: targetDeviceRateHz,
            strategy: settings.rateSwitchStrategy,
            settleDelayMs: settings.dacSettleDelayMs,
            sessionModeOption: settings.sessionMode,
            bassReinit: { [weak self] hz in self?.reinitBassDeviceSampleRateLocked(hz) ?? false }
        )

        if wantDop && !neg.matchedTarget {
            if dsdMode == .dop {
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.backendDidFailTrack(
                        track: track,
                        code: "dop_rate_lock_failed",
                        message: "DoP 安全拦截：外接 DAC 未能锁定载波采样率 \(targetDeviceRateHz) Hz（会话 \(neg.sessionActualHz) Hz，BASS \(neg.bassDeviceHz) Hz）。已阻止输出以防全幅噪音。"
                    )
                }
                return
            }
            // In .auto mode, fall back cleanly to DSD -> PCM
            let fallbackRate = resolvePcmTargetRateForCurrentRoute(preferred: settings.dsdPcmTargetRateHz)
            _ = sessionManager.negotiateSampleRate(
                targetHz: fallbackRate,
                strategy: settings.rateSwitchStrategy,
                settleDelayMs: settings.dacSettleDelayMs,
                sessionModeOption: settings.sessionMode,
                bassReinit: { [weak self] hz in self?.reinitBassDeviceSampleRateLocked(hz) ?? false }
            )
            startPcmPipelineLocked(
                track: track,
                probed: probed,
                targetPcmRate: fallbackRate,
                nextTrack: nextTrack,
                startPositionSeconds: startPositionSeconds,
                settings: settings
            )
            return
        }

        if wantDop {
            startDopPipelineLocked(
                track: track,
                probed: probed,
                startPositionSeconds: startPositionSeconds,
                settings: settings
            )
        } else {
            let openRate = probed.isDsd ? targetDeviceRateHz : probed.sampleRateHz
            startPcmPipelineLocked(
                track: track,
                probed: probed,
                targetPcmRate: openRate,
                nextTrack: nextTrack,
                startPositionSeconds: startPositionSeconds,
                settings: settings
            )
        }
    }

    private func startDopPipelineLocked(
        track: TrackSpec,
        probed: AudioFormatSignature,
        startPositionSeconds: Double,
        settings: EngineSettings
    ) {
        guard let dop = DopPassthroughStream(
            filePath: track.filePath,
            isPrePackagedDopWav: track.isPrePackagedDopWav,
            leadSilenceMs: settings.dopSilenceLeadMs,
            logger: logger
        ) else {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.backendDidFailTrack(
                    track: track,
                    code: "dop_stream_create_failed",
                    message: "创建 DoP 透传流失败。"
                )
            }
            return
        }

        if startPositionSeconds > 0 {
            _ = dop.seek(to: startPositionSeconds, leadSilenceMs: settings.dopSilenceLeadMs)
        }

        dop.onNaturalEnd = { [weak self] in
            guard let self else { return }
            self.engineQueue.async {
                guard self.dopStream === dop else { return }
                self.cancelDopWatchdogLocked()
                self.sessionManager.setActiveStreamExpectation(isDop: false, expectedRateHz: nil)
                self.isPlayingState = false
                self.isPausedState = false
                DispatchQueue.main.async {
                    self.delegate?.backendDidCompleteTrack(track: track)
                }
            }
        }

        self.dopStream = dop
        self.activeTrack = track
        self.activeFormat = AudioFormatSignature(
            sampleRateHz: dop.carrierRateHz,
            channels: dop.channels,
            validBits: 1,
            isDsd: true,
            dsdRateHz: dop.dsdRateHz,
            isDop: true,
            codecName: probed.codecName
        )
        self.cachedDurationSeconds = dop.durationSeconds()
        self.cachedPositionSeconds = startPositionSeconds

        _ = BASS_Start()
        BASS_SetConfig(DWORD(BASS_CONFIG_GVOL_STREAM), 10000)
        BASS_ChannelSetAttribute(dop.outputHandle, DWORD(BASS_ATTRIB_VOL), 1.0)
        if BASS_ChannelPlay(dop.outputHandle, 1) == 0 {
            let err = BASS_ErrorGetCode()
            dop.releaseResources()
            self.dopStream = nil
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.backendDidFailTrack(
                    track: track,
                    code: "dop_play_failed",
                    message: "启动 DoP 播放失败（BASS 错误 \(err)）。"
                )
            }
            return
        }

        self.isPlayingState = true
        self.isPausedState = false
        self.sessionManager.setActiveStreamExpectation(isDop: true, expectedRateHz: dop.carrierRateHz)
        self.startDopWatchdogLocked(carrierHz: dop.carrierRateHz, dopHandle: dop.outputHandle)
        self.refreshSignalPathLocked()
        let sigSnap = self.lastSignalPath
        DispatchQueue.main.async {
            self.delegate?.backendDidStartPlaying(track: track, signalPath: sigSnap)
        }
    }

    private func startPcmPipelineLocked(
        track: TrackSpec,
        probed: AudioFormatSignature,
        targetPcmRate: Int,
        nextTrack: TrackSpec?,
        startPositionSeconds: Double,
        settings: EngineSettings
    ) {
        guard let srcHandle = openDecodingStreamLocked(
            track: track,
            forceDsdToPcmRate: probed.isDsd ? targetPcmRate : nil
        ) else {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.backendDidFailTrack(
                    track: track,
                    code: "pcm_decode_failed",
                    message: "解码打开 \(track.fileName) 失败。"
                )
            }
            return
        }

        var srcInfo = BASS_CHANNELINFO()
        guard BASS_ChannelGetInfo(srcHandle, &srcInfo) != 0 else {
            BASS_StreamFree(srcHandle)
            return
        }

        let mixerFreq = Int(srcInfo.freq)
        let mixerChans = Int(srcInfo.chans)
        let mixerFlags = DWORD(BASS_SAMPLE_FLOAT | BASS_MIXER_QUEUE | BASS_MIXER_NONSTOP | BASS_MIXER_POSEX)
        let mixer = BASS_Mixer_StreamCreate(UInt32(mixerFreq), UInt32(mixerChans), mixerFlags)
        guard mixer != 0 else {
            let err = BASS_ErrorGetCode()
            BASS_StreamFree(srcHandle)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.backendDidFailTrack(
                    track: track,
                    code: "mixer_create_failed",
                    message: "创建 BASSmix 流失败（错误 \(err)）。"
                )
            }
            return
        }

        BASS_SetConfig(DWORD(BASS_CONFIG_GVOL_STREAM), 10000)
        BASS_ChannelSetAttribute(mixer, DWORD(BASS_ATTRIB_MIXER_VOL), 1.0)
        BASS_ChannelSetAttribute(mixer, DWORD(BASS_ATTRIB_PAN), 0.0)

        let nonZeroStartFade = startPositionSeconds > 0.005
        if nonZeroStartFade {
            let startBytes = BASS_ChannelSeconds2Bytes(srcHandle, startPositionSeconds)
            if startBytes != UInt64.max {
                BASS_ChannelSetPosition(srcHandle, startBytes, DWORD(BASS_POS_BYTE))
            }
            BASS_ChannelSetAttribute(mixer, DWORD(BASS_ATTRIB_NORAMP), 0.0)
            BASS_ChannelSetAttribute(mixer, DWORD(BASS_ATTRIB_VOL), 0.0)
        } else {
            // BASS_ATTRIB_NORAMP = 2 disables ramp-in ONLY so sample 0 is 100% bit-exact while keeping BASS ramp-out intact.
            BASS_ChannelSetAttribute(
                mixer,
                DWORD(BASS_ATTRIB_NORAMP),
                settings.strictBitPerfectNoRampIn ? 2.0 : 0.0
            )
            BASS_ChannelSetAttribute(mixer, DWORD(BASS_ATTRIB_VOL), 1.0)
        }

        let chanFlags = DWORD(BASS_MIXER_CHAN_NORAMPIN | BASS_MIXER_CHAN_AUTOFREE)
        guard BASS_Mixer_StreamAddChannel(mixer, srcHandle, chanFlags) != 0 else {
            let err = BASS_ErrorGetCode()
            BASS_StreamFree(srcHandle)
            BASS_StreamFree(mixer)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.backendDidFailTrack(
                    track: track,
                    code: "mixer_add_failed",
                    message: "添加音源至混音器失败（错误 \(err)）。"
                )
            }
            return
        }

        self.mixerStream = mixer
        self.activeSource = srcHandle
        self.activeTrack = track
        let sig = AudioFormatSignature(
            sampleRateHz: mixerFreq,
            channels: mixerChans,
            validBits: probed.validBits,
            isDsd: probed.isDsd,
            dsdRateHz: probed.dsdRateHz,
            isDop: false,
            codecName: probed.codecName
        )
        self.activeFormat = sig

        let lenBytes = BASS_ChannelGetLength(srcHandle, DWORD(BASS_POS_BYTE))
        let durSecs = lenBytes != UInt64.max ? BASS_ChannelBytes2Seconds(srcHandle, lenBytes) : 0
        self.cachedDurationSeconds = (durSecs.isFinite && durSecs > 0) ? durSecs : 0
        self.cachedPositionSeconds = startPositionSeconds

        installSourceEndSyncLocked(sourceHandle: srcHandle, track: track, signature: sig)

        if let nextTrack {
            tryQueueCompatibleTrackLocked(nextTrack: nextTrack, activeSignature: sig)
        }

        _ = BASS_Start()
        if BASS_ChannelPlay(mixer, 0) == 0 {
            let err = BASS_ErrorGetCode()
            teardownStreamsLocked(stopDevice: false)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.backendDidFailTrack(
                    track: track,
                    code: "mixer_play_failed",
                    message: "启动播放失败（BASS 错误 \(err)）。"
                )
            }
            return
        }

        if nonZeroStartFade {
            let rampMs = max(16, settings.pcmFadeMs)
            BASS_ChannelSlideAttribute(mixer, DWORD(BASS_ATTRIB_VOL), 1.0, DWORD(rampMs))
            self.scheduleRestoreNorampLocked(afterMs: rampMs + 25)
        }

        self.isPlayingState = true
        self.isPausedState = false
        self.sessionManager.setActiveStreamExpectation(isDop: false, expectedRateHz: mixerFreq)
        self.refreshSignalPathLocked()
        let sigSnap = self.lastSignalPath
        DispatchQueue.main.async {
            self.delegate?.backendDidStartPlaying(track: track, signalPath: sigSnap)
        }
    }

    private func tryQueueCompatibleTrackLocked(nextTrack: TrackSpec, activeSignature: AudioFormatSignature) {
        guard mixerStream != 0, !activeSignature.isDsd, !activeSignature.isDop else { return }
        guard !nextTrack.isPrePackagedDopWav else { return }
        let ext = URL(fileURLWithPath: nextTrack.filePath).pathExtension.lowercased()
        guard ext != "dsf" && ext != "dff" else { return }

        // Open once with BASS_ASYNCFILE and attach directly if compatible (no double-open stall at seam).
        guard let nextSrc = openDecodingStreamLocked(track: nextTrack, forceDsdToPcmRate: nil) else {
            return
        }
        guard let nextSig = inspectChannelSignatureLocked(handle: nextSrc),
              AudioFormatSignature.isGaplessCompatible(lhs: activeSignature, rhs: nextSig) else {
            BASS_StreamFree(nextSrc)
            return
        }

        let chanFlags = DWORD(BASS_MIXER_CHAN_NORAMPIN | BASS_MIXER_CHAN_AUTOFREE)
        if BASS_Mixer_StreamAddChannel(mixerStream, nextSrc, chanFlags) != 0 {
            queuedNextSource = nextSrc
            queuedNextTrack = nextTrack
            queuedNextFormat = nextSig
            installSourceEndSyncLocked(sourceHandle: nextSrc, track: nextTrack, signature: nextSig)
            logger.log(
                event: "gapless-queued",
                category: "gapless",
                message: "Queued compatible next track \(nextTrack.fileName) (\(nextSig.sampleRateHz) Hz / \(nextSig.channels)ch)",
                fields: ["nextFile": nextTrack.fileName, "rateHz": nextSig.sampleRateHz]
            )
        } else {
            BASS_StreamFree(nextSrc)
        }
    }

    private func installSourceEndSyncLocked(sourceHandle: HSTREAM, track: TrackSpec, signature: AudioFormatSignature) {
        let context = SyncContext(engine: self, sourceHandle: sourceHandle, track: track, signature: signature)
        let ptr = Unmanaged.passRetained(context).toOpaque()
        // BASS_SYNC_FREE releases the retained context only when BASS finishes freeing sourceHandle.
        let freeSync = BASS_ChannelSetSync(
            sourceHandle,
            DWORD(BASS_SYNC_FREE) | DWORD(BASS_SYNC_ONETIME),
            0,
            bassSourceFreedCallback,
            ptr
        )
        if freeSync == 0 {
            Unmanaged<SyncContext>.fromOpaque(ptr).release()
            return
        }
        _ = BASS_Mixer_ChannelSetSync(
            sourceHandle,
            DWORD(BASS_SYNC_END) | DWORD(BASS_SYNC_ONETIME),
            0,
            bassSourcePlaytimeEndCallback,
            ptr
        )
    }

    fileprivate func handleSourceEndedPlaytime(sourceHandle: HSTREAM, track: TrackSpec) {
        engineQueue.async { [weak self] in
            guard let self else { return }
            guard self.mixerStream != 0, self.activeSource == sourceHandle else { return }

            if self.queuedNextSource != 0, let nextTrack = self.queuedNextTrack, let nextFmt = self.queuedNextFormat {
                // Seamless gapless transition occurred at playtime boundary!
                self.activeSource = self.queuedNextSource
                self.activeTrack = nextTrack
                self.activeFormat = nextFmt
                self.queuedNextSource = 0
                self.queuedNextTrack = nil
                self.queuedNextFormat = nil

                let lenBytes = BASS_ChannelGetLength(self.activeSource, DWORD(BASS_POS_BYTE))
                let dur = lenBytes != UInt64.max ? BASS_ChannelBytes2Seconds(self.activeSource, lenBytes) : 0
                self.cachedDurationSeconds = (dur.isFinite && dur > 0) ? dur : 0
                self.cachedPositionSeconds = 0

                self.refreshSignalPathLocked()
                let sigSnap = self.lastSignalPath
                self.logger.log(
                    event: "gapless-advanced",
                    category: "gapless",
                    message: "Gapless playtime transition \(track.fileName) -> \(nextTrack.fileName)",
                    fields: ["from": track.fileName, "to": nextTrack.fileName, "rateHz": nextFmt.sampleRateHz]
                )
                DispatchQueue.main.async {
                    self.delegate?.backendDidAdvanceGaplessly(to: nextTrack, signalPath: sigSnap)
                }
            } else {
                // No compatible next track queued: allow BASS_MIXER_NONSTOP to push 30ms digital zeros before switching rate
                Thread.sleep(forTimeInterval: 0.030)
                self.sessionManager.setActiveStreamExpectation(isDop: false, expectedRateHz: nil)
                self.isPlayingState = false
                self.isPausedState = false
                self.activeSource = 0
                DispatchQueue.main.async {
                    self.delegate?.backendDidCompleteTrack(track: track)
                }
            }
        }
    }

    private func inspectChannelSignatureLocked(handle: HSTREAM) -> AudioFormatSignature? {
        var info = BASS_CHANNELINFO()
        guard BASS_ChannelGetInfo(handle, &info) != 0 else { return nil }
        let isDsd = info.ctype == DWORD(BASS_CTYPE_STREAM_DSD)
        var dsdRateFloat: Float = 0
        if isDsd {
            _ = BASS_ChannelGetAttribute(handle, DWORD(BASS_ATTRIB_DSD_RATE), &dsdRateFloat)
        }
        let bits = Int(info.origres & 0xFFFF)
        return AudioFormatSignature(
            sampleRateHz: Int(info.freq),
            channels: Int(info.chans),
            validBits: isDsd ? 1 : (bits > 0 ? bits : 16),
            isDsd: isDsd,
            dsdRateHz: Int(dsdRateFloat.rounded()),
            isDop: false,
            codecName: Self.codecName(from: info.ctype)
        )
    }

    private func probeFileFormatLocked(
        track: TrackSpec,
        dsdMode: DsdOutputMode,
        settings: EngineSettings
    ) -> AudioFormatSignature? {
        if track.isPrePackagedDopWav {
            guard let h = openDecodingStreamLocked(track: track, forceDsdToPcmRate: nil) else { return nil }
            defer { BASS_StreamFree(h) }
            var info = BASS_CHANNELINFO()
            guard BASS_ChannelGetInfo(h, &info) != 0 else { return nil }
            let bits = Int(info.origres & 0xFFFF)
            return AudioFormatSignature(
                sampleRateHz: Int(info.freq),
                channels: Int(info.chans),
                validBits: bits > 0 ? bits : 24,
                isDsd: true,
                dsdRateHz: Int(info.freq) * 16,
                isDop: dsdMode != .pcm,
                codecName: "DoP WAV Carrier"
            )
        }

        let ext = URL(fileURLWithPath: track.filePath).pathExtension.lowercased()
        if ext == "dsf" || ext == "dff" {
            let dsdHandle: HSTREAM = track.filePath.withCString { cPath in
                BASS_DSD_StreamCreateFile(
                    DWORD(BASS_FILE_NAME),
                    cPath,
                    0,
                    0,
                    DWORD(BASS_DSD_DOP | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE),
                    0
                )
            }
            guard dsdHandle != 0 else { return nil }
            defer { BASS_StreamFree(dsdHandle) }
            var info = BASS_CHANNELINFO()
            guard BASS_ChannelGetInfo(dsdHandle, &info) != 0 else { return nil }
            var dsdRateFloat: Float = 0
            if BASS_ChannelGetAttribute(dsdHandle, DWORD(BASS_ATTRIB_DSD_RATE), &dsdRateFloat) == 0 {
                dsdRateFloat = Float(info.freq * 16)
            }
            return AudioFormatSignature(
                sampleRateHz: Int(info.freq),
                channels: Int(info.chans),
                validBits: 1,
                isDsd: true,
                dsdRateHz: Int(dsdRateFloat.rounded()),
                isDop: false,
                codecName: ext.uppercased()
            )
        }

        guard let h = openDecodingStreamLocked(track: track, forceDsdToPcmRate: nil) else { return nil }
        defer { BASS_StreamFree(h) }
        return inspectChannelSignatureLocked(handle: h)
    }

    private func openDecodingStreamLocked(track: TrackSpec, forceDsdToPcmRate: Int?) -> HSTREAM? {
        let ext = URL(fileURLWithPath: track.filePath).pathExtension.lowercased()
        let handle: HSTREAM = track.filePath.withCString { cPath in
            if (ext == "dsf" || ext == "dff"), let targetRate = forceDsdToPcmRate {
                return BASS_DSD_StreamCreateFile(
                    DWORD(BASS_FILE_NAME),
                    cPath,
                    0,
                    0,
                    DWORD(BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE),
                    DWORD(targetRate)
                )
            } else {
                var flags = DWORD(BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT | BASS_ASYNCFILE)
                if ext == "mp3" || ext == "ogg" || ext == "aac" {
                    flags |= DWORD(BASS_STREAM_PRESCAN)
                }
                return BASS_StreamCreateFile(
                    DWORD(BASS_FILE_NAME),
                    cPath,
                    0,
                    0,
                    flags
                )
            }
        }
        return handle != 0 ? handle : nil
    }

    private func resolvePcmTargetRateForCurrentRoute(preferred: Int) -> Int {
        let route = sessionManager.currentRouteKind()
        if route == .speaker || route == .receiver || route == .bluetoothA2dp || route == .bluetoothLe || route == .bluetoothHfp {
            return 48000
        }
        return preferred
    }

    private func rampDownAndDrainPcmLocked(stream: HSTREAM, fadeMs: Int) {
        guard stream != 0 else { return }
        BASS_ChannelSetAttribute(stream, DWORD(BASS_ATTRIB_NORAMP), 0.0)
        let clamped = max(0, fadeMs)
        if clamped > 0 {
            BASS_ChannelSlideAttribute(stream, DWORD(BASS_ATTRIB_VOL), 0.0, DWORD(clamped))
            var waitMs = 0
            let maxWait = clamped + 30
            while BASS_ChannelIsSliding(stream, DWORD(BASS_ATTRIB_VOL)) != 0 && waitMs < maxWait {
                Thread.sleep(forTimeInterval: 0.004)
                waitMs += 4
            }
        } else {
            BASS_ChannelSetAttribute(stream, DWORD(BASS_ATTRIB_VOL), 0.0)
        }
        // Let CoreAudio consume one mixer update period (20ms) of zeroed tail before stopping/pausing.
        Thread.sleep(forTimeInterval: 0.022)
    }

    private func scheduleRestoreNorampLocked(afterMs: Int) {
        norampRestoreWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.mixerStream != 0, self.isPlayingState && !self.isPausedState else { return }
            let val: Float = self.lastSettings.strictBitPerfectNoRampIn ? 2.0 : 0.0
            BASS_ChannelSetAttribute(self.mixerStream, DWORD(BASS_ATTRIB_NORAMP), val)
        }
        norampRestoreWorkItem = item
        engineQueue.asyncAfter(deadline: .now() + .milliseconds(max(10, afterMs)), execute: item)
    }

    private func startDopWatchdogLocked(carrierHz: Int, dopHandle: HSTREAM) {
        cancelDopWatchdogLocked()
        let timer = DispatchSource.makeTimerSource(queue: engineQueue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self, self.isPlayingState && !self.isPausedState,
                  let currentDop = self.dopStream, currentDop.outputHandle == dopHandle else {
                self?.cancelDopWatchdogLocked()
                return
            }
            let profile = self.sessionManager.currentProfile()
            var violation: DopSafetyFailure?
            if profile.routeKind != .usbAudio {
                violation = .nonUsbRoute(profile.routeKind)
            } else if profile.outputVolume < 0.999 {
                violation = .systemVolumeNotFull(profile.outputVolume)
            } else if profile.currentSessionSampleRateHz != carrierHz ||
                        (profile.bassDeviceSampleRateHz > 0 && profile.bassDeviceSampleRateHz != carrierHz) {
                let actual = profile.currentSessionSampleRateHz != carrierHz
                    ? profile.currentSessionSampleRateHz
                    : profile.bassDeviceSampleRateHz
                violation = .midStreamRateDrop(expectedHz: carrierHz, actualHz: actual)
            } else {
                var chVol: Float = 1.0
                _ = BASS_ChannelGetAttribute(dopHandle, DWORD(BASS_ATTRIB_VOL), &chVol)
                let globalVol = BASS_GetConfig(DWORD(BASS_CONFIG_GVOL_STREAM))
                if abs(chVol - 1.0) > 0.001 || globalVol != 10000 {
                    BASS_SetConfig(DWORD(BASS_CONFIG_GVOL_STREAM), 10000)
                    BASS_ChannelSetAttribute(dopHandle, DWORD(BASS_ATTRIB_VOL), 1.0)
                    violation = .midStreamRateDrop(expectedHz: carrierHz, actualHz: profile.currentSessionSampleRateHz)
                }
            }

            if let v = violation {
                self.logger.log(
                    event: "dop-watchdog-halt",
                    category: "safety",
                    message: v.message,
                    fields: ["code": v.code, "sessionHz": profile.currentSessionSampleRateHz, "bassHz": profile.bassDeviceSampleRateHz, "vol": profile.outputVolume]
                )
                self.emergencySafetyHaltLocked(reason: v.code)
            }
        }
        dopWatchdogTimer = timer
        timer.resume()
    }

    private func cancelDopWatchdogLocked() {
        dopWatchdogTimer?.cancel()
        dopWatchdogTimer = nil
    }

    private func fadeOutAndTeardownLocked(fadeMs: Int, dopTrailMs: Int, completion: @escaping () -> Void) {
        cancelDopWatchdogLocked()
        norampRestoreWorkItem?.cancel()
        if let dop = dopStream {
            dop.beginTrailSilenceAndStop(trailMs: dopTrailMs) { [weak self] in
                self?.engineQueue.async {
                    self?.teardownStreamsLocked(stopDevice: false)
                    completion()
                }
            }
            return
        }
        if mixerStream != 0 && isPlayingState && !isPausedState {
            rampDownAndDrainPcmLocked(stream: mixerStream, fadeMs: max(16, fadeMs))
        }
        teardownStreamsLocked(stopDevice: false)
        completion()
    }

    private func teardownStreamsLocked(stopDevice: Bool) {
        cancelDopWatchdogLocked()
        norampRestoreWorkItem?.cancel()
        if let dop = dopStream {
            dop.releaseResources()
            dopStream = nil
        }
        if mixerStream != 0 {
            BASS_ChannelStop(mixerStream)
            BASS_StreamFree(mixerStream)
            mixerStream = 0
        }
        activeSource = 0
        queuedNextSource = 0
        queuedNextTrack = nil
        queuedNextFormat = nil
        sessionManager.setActiveStreamExpectation(isDop: false, expectedRateHz: nil)
        if stopDevice {
            _ = BASS_Pause()
        }
    }

    private func finalizeStopLocked(reason: String?, completion: (() -> Void)?) {
        isPlayingState = false
        isPausedState = false
        cachedPositionSeconds = 0
        cachedDurationSeconds = 0
        activeTrack = nil
        activeFormat = nil
        lastSignalPath = .idle
        sessionManager.setActiveStreamExpectation(isDop: false, expectedRateHz: nil)
        scheduleIdlePauseLocked()
        DispatchQueue.main.async {
            self.delegate?.backendDidStop(reason: reason)
            self.delegate?.backendDidUpdateSignalPath(.idle)
            completion?()
        }
    }

    private func scheduleIdlePauseLocked() {
        idlePauseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.isPlayingState {
                _ = BASS_Pause()
                self.logger.log(event: "bass-idle-paused", category: "power", message: "BASS device paused after 30s idle timeout")
            }
        }
        idlePauseWorkItem = item
        engineQueue.asyncAfter(deadline: .now() + 30.0, execute: item)
    }

    private func cancelIdlePauseLocked() {
        idlePauseWorkItem?.cancel()
        idlePauseWorkItem = nil
    }

    private func startProgressTimerLocked() {
        progressTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: engineQueue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            guard let self, self.isPlayingState && !self.isPausedState else { return }
            let pos = self.computePositionLocked()
            let dur = self.cachedDurationSeconds
            self.cachedPositionSeconds = pos
            DispatchQueue.main.async {
                self.delegate?.backendDidUpdatePosition(seconds: pos, durationSeconds: dur)
            }
        }
        progressTimer = timer
        timer.resume()
    }

    private func computePositionLocked() -> Double {
        if let dop = dopStream {
            return dop.currentPositionSeconds()
        }
        if activeSource != 0 {
            let bytes = BASS_Mixer_ChannelGetPosition(activeSource, DWORD(BASS_POS_BYTE))
            if bytes != UInt64.max {
                let secs = BASS_ChannelBytes2Seconds(activeSource, bytes)
                if secs.isFinite && secs >= 0 {
                    return secs
                }
            }
        }
        return cachedPositionSeconds
    }

    private func refreshSignalPathLocked() {
        guard let fmt = activeFormat else {
            lastSignalPath = .idle
            return
        }
        let profile = sessionManager.currentProfile()
        let isDop = fmt.isDop
        let engineRate = isDop ? AudioFormatSignature.dopCarrierHz(forDsdRate: fmt.dsdRateHz) : fmt.sampleRateHz
        let sessionRate = profile.currentSessionSampleRateHz
        let bassRate = profile.bassDeviceSampleRateHz
        let resampled = (engineRate > 0 && sessionRate > 0 && engineRate != sessionRate) ||
            (engineRate > 0 && bassRate > 0 && engineRate != bassRate)

        let pipelineMode: String
        if isDop {
            pipelineMode = "BASSDSD DoP 直通（零混音 / 零斜坡）"
        } else if fmt.isDsd {
            pipelineMode = "DSD → PCM 转换（BASSmix 浮点队列）"
        } else {
            pipelineMode = "BASSmix 浮点直通队列（Unity Gain）"
        }

        let bitPerfectCandidate: Bool
        if isDop {
            bitPerfectCandidate = !resampled && profile.routeKind == .usbAudio && profile.outputVolume >= 0.999
        } else if fmt.isDsd {
            bitPerfectCandidate = false
        } else {
            bitPerfectCandidate = !resampled &&
                (profile.routeKind == .usbAudio || profile.routeKind == .wiredHeadphones || profile.routeKind == .lineOut || profile.routeKind == .hdmi) &&
                fmt.validBits <= 24
        }

        let statusSummary: String
        if isDop {
            statusSummary = bitPerfectCandidate
                ? "DoP 载波锁定 \(engineRate) Hz（请在 DAC 面板核对 DSD 指示灯）"
                : "DoP 链路未完全匹配（会话 \(sessionRate) Hz）"
        } else if fmt.isDsd {
            statusSummary = "已转为 \(engineRate) Hz PCM 输出（非原生 DoP）"
        } else if resampled {
            statusSummary = "系统发生采样率转换：引擎 \(engineRate) Hz → 会话 \(sessionRate) Hz"
        } else {
            statusSummary = "原采样率匹配 \(engineRate) Hz（无应用层重采样）"
        }

        let snapshot = SignalPathSnapshot(
            sourceCodec: fmt.codecName,
            sourceSampleRateHz: fmt.isDsd ? fmt.dsdRateHz : fmt.sampleRateHz,
            sourceValidBits: fmt.validBits,
            sourceChannels: fmt.channels,
            sourceIsDsd: fmt.isDsd,
            sourceDsdRateHz: fmt.dsdRateHz,
            enginePipelineMode: pipelineMode,
            engineOutputSampleRateHz: engineRate,
            engineOutputChannels: fmt.channels,
            engineFloatPrecision: isDop ? "24-bit DoP over IEEE Float32" : "IEEE Float32 (24-bit exact integer mantissa)",
            engineVolumeGain: 1.0,
            mixerFlags: isDop ? "BASS_DSD_DOP|NORAMP=1|DOWNMIX=0" : "BASS_MIXER_QUEUE|NONSTOP|POSEX|NORAMPIN|NORAMP=2",
            gaplessNextTrackQueued: queuedNextSource != 0,
            gaplessNextTrackName: queuedNextTrack?.fileName,
            sessionCategory: "AVAudioSessionCategoryPlayback",
            sessionMode: lastSettings.sessionMode.rawValue,
            sessionRequestedRateHz: sessionManager.lastRequestedSampleRateHz,
            sessionActualRateHz: sessionRate,
            bassDeviceRateHz: bassRate,
            routeKind: profile.routeKind,
            routeName: profile.deviceName,
            outputVolume: profile.outputVolume,
            resampledBySystem: resampled,
            bitPerfectCandidate: bitPerfectCandidate,
            dopActive: isDop,
            hardwareDisplayUnverifiedNote: "iOS 无法回读外接 DAC 实际接收位深及 DoP 锁定状态，最终以硬件面板与数字采集为准。",
            statusSummary: statusSummary
        )
        lastSignalPath = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.backendDidUpdateSignalPath(snapshot)
        }
    }

    static func codecName(from ctype: DWORD) -> String {
        if (ctype & DWORD(BASS_CTYPE_STREAM_WAV)) != 0 {
            let sub = ctype & 0xFFFF
            if sub == 3 { return "WAV Float" }
            return "WAV PCM"
        }
        switch ctype {
        case DWORD(BASS_CTYPE_STREAM_FLAC): return "FLAC"
        case DWORD(BASS_CTYPE_STREAM_FLAC_OGG): return "FLAC (Ogg)"
        case DWORD(BASS_CTYPE_STREAM_WV): return "WavPack"
        case DWORD(BASS_CTYPE_STREAM_APE): return "Monkey's Audio (APE)"
        case DWORD(BASS_CTYPE_STREAM_OPUS): return "Opus"
        case DWORD(BASS_CTYPE_STREAM_DSD): return "DSD"
        case DWORD(BASS_CTYPE_STREAM_CA): return "CoreAudio (ALAC/AAC)"
        case DWORD(BASS_CTYPE_STREAM_MP3): return "MP3"
        case DWORD(BASS_CTYPE_STREAM_OGG): return "Vorbis"
        case DWORD(BASS_CTYPE_STREAM_AIFF): return "AIFF"
        default: return "Unknown (0x\(String(format: "%X", ctype)))"
        }
    }
}

private final class SyncContext {
    weak var engine: BassAudioEngine?
    let sourceHandle: HSTREAM
    let track: TrackSpec
    let signature: AudioFormatSignature

    init(engine: BassAudioEngine, sourceHandle: HSTREAM, track: TrackSpec, signature: AudioFormatSignature) {
        self.engine = engine
        self.sourceHandle = sourceHandle
        self.track = track
        self.signature = signature
    }
}

private func bassSourcePlaytimeEndCallback(
    handle: HSYNC,
    channel: DWORD,
    data: DWORD,
    user: UnsafeMutableRawPointer?
) {
    guard let user else { return }
    let ctx = Unmanaged<SyncContext>.fromOpaque(user).takeUnretainedValue()
    ctx.engine?.handleSourceEndedPlaytime(sourceHandle: ctx.sourceHandle, track: ctx.track)
}

private func bassSourceFreedCallback(
    handle: HSYNC,
    channel: DWORD,
    data: DWORD,
    user: UnsafeMutableRawPointer?
) {
    guard let user else { return }
    Unmanaged<SyncContext>.fromOpaque(user).release()
}
