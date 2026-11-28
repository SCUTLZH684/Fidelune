import AVFoundation
import Foundation

struct RateNegotiationResult: Equatable {
    let requestedHz: Int
    let sessionActualHz: Int
    let bassDeviceHz: Int
    let matchedTarget: Bool
    let routeKind: OutputRouteKind
    let strategyUsed: RateSwitchStrategy
    let settleElapsedMs: Int
    let phaseReached: String
    let initialSessionHz: Int
    let initialBassHz: Int
    let categoryOptionsRaw: UInt
    let sessionError: String?

    func toDictionary() -> [String: Any] {
        [
            "requestedHz": requestedHz,
            "sessionActualHz": sessionActualHz,
            "bassDeviceHz": bassDeviceHz,
            "matchedTarget": matchedTarget,
            "routeKind": routeKind.rawValue,
            "strategyUsed": strategyUsed.rawValue,
            "settleElapsedMs": settleElapsedMs,
            "phaseReached": phaseReached,
            "initialSessionHz": initialSessionHz,
            "initialBassHz": initialBassHz,
            "categoryOptionsRaw": Int(categoryOptionsRaw),
            "sessionError": sessionError as Any,
        ]
    }
}

protocol DacSessionManagerDelegate: AnyObject {
    func sessionDidUpdateProfile(_ profile: DacCapabilityProfile)
    func sessionDidRequestPauseForRouteRemoval(route: OutputRouteKind)
    func sessionDidObserveRouteArrival(profile: DacCapabilityProfile)
    func sessionDidDetectUnexpectedUsbRateDrop(expectedHz: Int, actualSessionHz: Int, actualBassHz: Int)
    func sessionDidBeginInterruption(wasPlaying: Bool)
    func sessionShouldResumeAfterInterruption()
    func sessionDidObserveMediaServicesLost()
    func sessionDidObserveMediaServicesReset()
    func sessionDidTriggerDopSafetyViolation(reason: DopSafetyFailure)
}

final class DacSessionManager: NSObject {
    private let adapter: AudioSessionAdapter
    private let rawSessionForKVO: AVAudioSession?
    private let logger: DiagnosticsSink
    private let notificationCenter: NotificationCenter
    private let sleepFn: (TimeInterval) -> Void

    weak var delegate: DacSessionManagerDelegate?

    private var volumeObservation: NSKeyValueObservation?
    private var observersRegistered = false
    private var startupConfigured = false

    private(set) var lastRequestedSampleRateHz: Int = 48000
    private(set) var isInterrupted: Bool = false
    private(set) var resumeAfterInterruption: Bool = false
    private(set) var pausedForRouteRemoval: Bool = false
    private(set) var userIntervenedDuringInterruption: Bool = false
    private(set) var isDopStreamActive: Bool = false
    private(set) var activeDopCarrierHz: Int?
    private(set) var expectedUsbPcmRateHz: Int?

    private var bassRateProvider: (() -> Int)?
    private var isPlayingProvider: (() -> Bool)?
    private var probedRatesByUID: [String: Set<Int>] = [:]

    init(
        adapter: AudioSessionAdapter = SystemAudioSessionAdapter(),
        rawSessionForKVO: AVAudioSession? = .sharedInstance(),
        notificationCenter: NotificationCenter = .default,
        logger: DiagnosticsSink = DiagnosticsLogger.shared,
        sleepFn: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.adapter = adapter
        self.rawSessionForKVO = rawSessionForKVO
        self.notificationCenter = notificationCenter
        self.logger = logger
        self.sleepFn = sleepFn
        super.init()
        registerObserversIfNeeded()
    }

    deinit {
        volumeObservation?.invalidate()
        notificationCenter.removeObserver(self)
    }

    func configureBindings(
        bassRateProvider: @escaping () -> Int,
        isPlayingProvider: @escaping () -> Bool
    ) {
        self.bassRateProvider = bassRateProvider
        self.isPlayingProvider = isPlayingProvider
    }

    /// Ensures exclusive AVAudioSession (.playback with options: []) without .mixWithOthers
    /// so Lock Screen / Remote Commands remain eligible and USB DAC clock negotiation is unshared.
    @discardableResult
    func configurePlaybackSession(modeOption: SessionModeOption = .defaultMode) -> String? {
        let avMode: AVAudioSession.Mode = (modeOption == .measurement) ? .measurement : .default
        let hadDrift = adapter.category != .playback ||
            adapter.mode != avMode ||
            adapter.categoryOptions.rawValue != 0 ||
            !startupConfigured
        var errorDesc: String?
        do {
            try adapter.setCategory(.playback, mode: avMode, options: [])
            try adapter.setActive(true, options: [])
            startupConfigured = true
            if hadDrift {
                logger.log(
                    event: "session-configured",
                    category: "session",
                    message: "Exclusive playback session asserted (mode=\(avMode.rawValue), options=\(adapter.categoryOptions.rawValue))",
                    fields: [
                        "category": adapter.category.rawValue,
                        "mode": avMode.rawValue,
                        "categoryOptionsRaw": Int(adapter.categoryOptions.rawValue),
                        "sampleRateHz": Int(adapter.sampleRate.rounded()),
                        "route": currentRouteKind().rawValue,
                    ]
                )
            }
        } catch {
            let nsErr = error as NSError
            errorDesc = "\(nsErr.domain) (\(nsErr.code)): \(nsErr.localizedDescription)"
            logger.log(
                event: "session-config-error",
                category: "session",
                message: "AVAudioSession configuration failed: \(errorDesc ?? "")",
                fields: [
                    "domain": nsErr.domain,
                    "code": nsErr.code,
                    "categoryOptionsRaw": Int(adapter.categoryOptions.rawValue),
                ]
            )
        }
        registerObserversIfNeeded()
        return errorDesc
    }

    func activateAtStartup(modeOption: SessionModeOption = .defaultMode) {
        _ = configurePlaybackSession(modeOption: modeOption)
    }

    func applySessionMode(_ modeOption: SessionModeOption) {
        _ = configurePlaybackSession(modeOption: modeOption)
    }

    func reactivateSession(modeOption: SessionModeOption = .defaultMode) {
        _ = configurePlaybackSession(modeOption: modeOption)
    }

    func setPreferredSampleRateDirect(_ targetHz: Int) -> String? {
        do {
            try adapter.setPreferredSampleRate(Double(targetHz))
            return nil
        } catch {
            let nsErr = error as NSError
            return "\(nsErr.domain) (\(nsErr.code)): \(nsErr.localizedDescription)"
        }
    }

    func currentRouteKind() -> OutputRouteKind {
        Self.mapPortType(adapter.primaryOutputPortType)
    }

    func currentProfile() -> DacCapabilityProfile {
        let routeKind = currentRouteKind()
        let portType = adapter.primaryOutputPortType?.rawValue ?? "none"
        let portName = adapter.primaryOutputPortName ?? routeKind.displayLabel
        let portUID = adapter.primaryOutputPortUID ?? portType
        let bassHz = bassRateProvider?() ?? 0
        let probed = Array(probedRatesByUID[portUID] ?? []).sorted()

        return DacCapabilityProfile(
            deviceName: portName,
            portType: portType,
            routeKind: routeKind,
            portUID: portUID,
            isUsbDac: routeKind == .usbAudio,
            currentSessionSampleRateHz: Int(adapter.sampleRate.rounded()),
            preferredSampleRateHz: Int(adapter.preferredSampleRate.rounded()),
            bassDeviceSampleRateHz: bassHz,
            outputChannels: adapter.outputNumberOfChannels,
            maxOutputChannels: adapter.maximumOutputNumberOfChannels,
            outputVolume: Double(adapter.outputVolume),
            ioBufferDurationMs: adapter.ioBufferDuration * 1000.0,
            outputLatencyMs: adapter.outputLatency * 1000.0,
            probedSupportedRatesHz: probed,
            supportsDopCandidate: routeKind.supportsDop && Double(adapter.outputVolume) >= 0.999,
            physicalBitDepthReadable: false
        )
    }

    func markUserStartedPlayback() {
        pausedForRouteRemoval = false
        isInterrupted = false
        resumeAfterInterruption = false
        userIntervenedDuringInterruption = false
    }

    func markUserCommandDuringInterruption() {
        if isInterrupted {
            userIntervenedDuringInterruption = true
            resumeAfterInterruption = false
        }
    }

    func setDopActive(_ active: Bool) {
        isDopStreamActive = active
        if !active {
            activeDopCarrierHz = nil
        }
    }

    func setActiveStreamExpectation(isDop: Bool, expectedRateHz: Int?) {
        if isDop {
            isDopStreamActive = true
            activeDopCarrierHz = expectedRateHz
            expectedUsbPcmRateHz = nil
        } else {
            isDopStreamActive = false
            activeDopCarrierHz = nil
            expectedUsbPcmRateHz = expectedRateHz
        }
    }

    func validateDopSafety(carrierHz: Int, userAcknowledged: Bool) -> Result<Void, DopSafetyFailure> {
        let route = currentRouteKind()
        guard route.supportsDop else {
            return .failure(.nonUsbRoute(route))
        }
        guard carrierHz > 0 && carrierHz <= 768_000 else {
            return .failure(.carrierRateUnsupported(carrierHz))
        }
        let vol = Double(adapter.outputVolume)
        guard vol >= 0.999 else {
            return .failure(.systemVolumeNotFull(vol))
        }
        guard userAcknowledged else {
            return .failure(.userSafetyNotAcknowledged)
        }
        return .success(())
    }

    func negotiateSampleRate(
        targetHz: Int,
        strategy: RateSwitchStrategy,
        settleDelayMs: Int,
        sessionModeOption: SessionModeOption = .defaultMode,
        bassReinit: (Int) -> Bool
    ) -> RateNegotiationResult {
        var sessionError = configurePlaybackSession(modeOption: sessionModeOption)
        let routeKind = currentRouteKind()
        lastRequestedSampleRateHz = targetHz

        let startTime = Date()
        let initialSessionHz = Int(adapter.sampleRate.rounded())
        let initialBassHz = bassRateProvider?() ?? 0

        if !routeKind.isWiredDacCapable && routeKind != .wiredHeadphones {
            if let err = setPreferredSampleRateDirect(targetHz) {
                sessionError = sessionError ?? err
            }
            let sessionHz = Int(adapter.sampleRate.rounded())
            let bassHz = bassRateProvider?() ?? 0
            let matched = (sessionHz == targetHz && bassHz == targetHz)
            let result = RateNegotiationResult(
                requestedHz: targetHz,
                sessionActualHz: sessionHz,
                bassDeviceHz: bassHz,
                matchedTarget: matched,
                routeKind: routeKind,
                strategyUsed: strategy,
                settleElapsedMs: 0,
                phaseReached: "non_wired_route",
                initialSessionHz: initialSessionHz,
                initialBassHz: initialBassHz,
                categoryOptionsRaw: adapter.categoryOptions.rawValue,
                sessionError: sessionError
            )
            logRateNegotiation(result)
            return result
        }

        if initialSessionHz == targetHz && initialBassHz == targetHz {
            recordProbedRate(targetHz)
            let result = RateNegotiationResult(
                requestedHz: targetHz,
                sessionActualHz: initialSessionHz,
                bassDeviceHz: initialBassHz,
                matchedTarget: true,
                routeKind: routeKind,
                strategyUsed: strategy,
                settleElapsedMs: 0,
                phaseReached: "already_matched",
                initialSessionHz: initialSessionHz,
                initialBassHz: initialBassHz,
                categoryOptionsRaw: adapter.categoryOptions.rawValue,
                sessionError: sessionError
            )
            logRateNegotiation(result)
            return result
        }

        var phaseReached = "unmatched"
        var matched = false

        // Phase 1: AVAudioSession preferredSampleRate + bounded polling (up to 450ms)
        if strategy != .bassReinit {
            if let err = setPreferredSampleRateDirect(targetHz) {
                sessionError = sessionError ?? err
            }
            if pollUntilMatched(targetHz: targetHz, timeoutMs: 450, stepMs: 25) {
                matched = true
                phaseReached = "phase1_sessionPreferred"
            }
        }

        // Phase 2: BASS_DEVICE_FREQ | BASS_DEVICE_REINIT + bounded polling (up to 1100ms for UAC2 clock relock)
        if !matched && strategy != .sessionPreferred {
            _ = bassReinit(targetHz)
            if let err = configurePlaybackSession(modeOption: sessionModeOption) {
                sessionError = sessionError ?? err
            }
            if let err = setPreferredSampleRateDirect(targetHz) {
                sessionError = sessionError ?? err
            }
            if pollUntilMatched(targetHz: targetHz, timeoutMs: 1100, stepMs: 25) {
                matched = true
                phaseReached = "phase2_bassReinit"
            }
        }

        // Phase 3: Clean session deactivation/reactivation cycle fallback if still mismatched in hybrid mode
        if !matched && strategy == .hybrid {
            do {
                try adapter.setActive(false, options: [])
            } catch {
                let nsErr = error as NSError
                sessionError = sessionError ?? "\(nsErr.domain) (\(nsErr.code))"
            }
            sleepFn(0.04)
            if let err = configurePlaybackSession(modeOption: sessionModeOption) {
                sessionError = sessionError ?? err
            }
            if let err = setPreferredSampleRateDirect(targetHz) {
                sessionError = sessionError ?? err
            }
            _ = bassReinit(targetHz)
            if pollUntilMatched(targetHz: targetHz, timeoutMs: 600, stepMs: 25) {
                matched = true
                phaseReached = "phase3_sessionCycle"
            } else {
                phaseReached = "phase3_unmatched"
            }
        }

        // Post-lock DAC mute-relay settle when clock changed
        let clockChanged = (initialSessionHz != targetHz || initialBassHz != targetHz)
        let clampedPostSettle = max(0, min(250, settleDelayMs))
        if matched && clockChanged && clampedPostSettle > 0 {
            sleepFn(TimeInterval(clampedPostSettle) / 1000.0)
        }

        let finalSessionHz = Int(adapter.sampleRate.rounded())
        let finalBassHz = bassRateProvider?() ?? 0
        matched = (finalSessionHz == targetHz) && (finalBassHz == targetHz)
        if matched {
            recordProbedRate(targetHz)
        } else if phaseReached == "unmatched" {
            phaseReached = "failed_\(strategy.rawValue)"
        }

        let elapsedMs = Int((Date().timeIntervalSince(startTime) * 1000.0).rounded())
        let result = RateNegotiationResult(
            requestedHz: targetHz,
            sessionActualHz: finalSessionHz,
            bassDeviceHz: finalBassHz,
            matchedTarget: matched,
            routeKind: routeKind,
            strategyUsed: strategy,
            settleElapsedMs: elapsedMs,
            phaseReached: phaseReached,
            initialSessionHz: initialSessionHz,
            initialBassHz: initialBassHz,
            categoryOptionsRaw: adapter.categoryOptions.rawValue,
            sessionError: sessionError
        )
        logRateNegotiation(result)

        let profile = currentProfile()
        delegate?.sessionDidUpdateProfile(profile)

        return result
    }

    func runUsbDacRateSweep(
        rates: [Int] = [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000],
        strategy: RateSwitchStrategy = .hybrid,
        settleDelayMs: Int = 80,
        sessionModeOption: SessionModeOption = .defaultMode,
        bassReinit: (Int) -> Bool
    ) -> [RateNegotiationResult] {
        var results: [RateNegotiationResult] = []
        for hz in rates {
            results.append(
                negotiateSampleRate(
                    targetHz: hz,
                    strategy: strategy,
                    settleDelayMs: settleDelayMs,
                    sessionModeOption: sessionModeOption,
                    bassReinit: bassReinit
                )
            )
        }
        let matchedRates = results.filter { $0.matchedTarget }.map { $0.requestedHz }
        logger.log(
            event: "dac-rate-sweep-completed",
            category: "dac",
            message: "USB DAC 8-rate handshake sweep: \(matchedRates.count)/\(results.count) matched",
            fields: [
                "matchedRates": matchedRates,
                "testedRates": rates,
                "route": currentRouteKind().rawValue,
            ]
        )
        return results
    }

    private func pollUntilMatched(targetHz: Int, timeoutMs: Int, stepMs: Int) -> Bool {
        let maxSteps = max(1, timeoutMs / max(1, stepMs))
        for step in 0..<maxSteps {
            let sHz = Int(adapter.sampleRate.rounded())
            let bHz = bassRateProvider?() ?? 0
            if sHz == targetHz && bHz == targetHz {
                return true
            }
            if step + 1 < maxSteps {
                sleepFn(TimeInterval(stepMs) / 1000.0)
            }
        }
        let sHz = Int(adapter.sampleRate.rounded())
        let bHz = bassRateProvider?() ?? 0
        return sHz == targetHz && bHz == targetHz
    }

    private func logRateNegotiation(_ res: RateNegotiationResult) {
        logger.log(
            event: "dac-rate-negotiated",
            category: "dac",
            message: "Requested \(res.requestedHz) Hz -> session \(res.sessionActualHz) Hz, BASS \(res.bassDeviceHz) Hz [\(res.phaseReached)]",
            fields: [
                "initialSessionHz": res.initialSessionHz,
                "initialBassHz": res.initialBassHz,
                "requestedHz": res.requestedHz,
                "preferredHz": Int(adapter.preferredSampleRate.rounded()),
                "sessionActualHz": res.sessionActualHz,
                "bassDeviceHz": res.bassDeviceHz,
                "matchedTarget": res.matchedTarget,
                "route": res.routeKind.rawValue,
                "strategy": res.strategyUsed.rawValue,
                "phaseReached": res.phaseReached,
                "categoryOptionsRaw": Int(res.categoryOptionsRaw),
                "sessionError": res.sessionError ?? "",
                "settleElapsedMs": res.settleElapsedMs,
            ]
        )
    }

    private func recordProbedRate(_ hz: Int) {
        let uid = adapter.primaryOutputPortUID ?? (adapter.primaryOutputPortType?.rawValue ?? "default")
        var set = probedRatesByUID[uid] ?? []
        set.insert(hz)
        probedRatesByUID[uid] = set
    }

    // MARK: - Observers & Interruption / Route State Machine

    private func registerObserversIfNeeded() {
        guard !observersRegistered else { return }
        observersRegistered = true

        notificationCenter.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleMediaServicesLost(_:)),
            name: AVAudioSession.mediaServicesWereLostNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleMediaServicesReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )

        if let rawSession = rawSessionForKVO {
            volumeObservation = rawSession.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let self, let newVol = change.newValue else { return }
                if self.isDopStreamActive && Double(newVol) < 0.999 {
                    let failure = DopSafetyFailure.systemVolumeNotFull(Double(newVol))
                    self.logger.log(
                        event: "dop-volume-safety-halt",
                        category: "safety",
                        message: failure.message,
                        fields: ["outputVolume": Double(newVol)]
                    )
                    self.delegate?.sessionDidTriggerDopSafetyViolation(reason: failure)
                }
                self.delegate?.sessionDidUpdateProfile(self.currentProfile())
            }
        }
    }

    @objc func handleRouteChange(_ note: Notification) {
        let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        let prevDesc = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        let previousPorts = prevDesc?.outputs.map { $0.portType.rawValue } ?? []
        let currentRoute = currentRouteKind()
        let profile = currentProfile()

        logger.log(
            event: "route-changed",
            category: "route",
            message: "Route changed (\(Self.describe(reason: reason))) -> \(profile.deviceName) [\(currentRoute.rawValue)]",
            fields: [
                "reason": reasonValue,
                "reasonText": Self.describe(reason: reason),
                "previousPorts": previousPorts,
                "currentRoute": currentRoute.rawValue,
                "deviceName": profile.deviceName,
                "sessionHz": profile.currentSessionSampleRateHz,
                "bassHz": profile.bassDeviceSampleRateHz,
                "categoryOptionsRaw": Int(adapter.categoryOptions.rawValue),
                "isDop": isDopStreamActive,
                "activeDopCarrierHz": activeDopCarrierHz ?? 0,
                "expectedUsbPcmRateHz": expectedUsbPcmRateHz ?? 0,
            ]
        )

        // Priority 1: Active DoP runtime safety interlock on ANY route/rate/volume anomaly
        if isDopStreamActive {
            var safetyViolation: DopSafetyFailure?
            if currentRoute != .usbAudio {
                safetyViolation = .nonUsbRoute(currentRoute)
            } else if profile.outputVolume < 0.999 {
                safetyViolation = .systemVolumeNotFull(profile.outputVolume)
            } else if let carrierHz = activeDopCarrierHz,
                      (profile.currentSessionSampleRateHz != carrierHz ||
                       (profile.bassDeviceSampleRateHz > 0 && profile.bassDeviceSampleRateHz != carrierHz)) {
                let actual = profile.currentSessionSampleRateHz != carrierHz
                    ? profile.currentSessionSampleRateHz
                    : profile.bassDeviceSampleRateHz
                safetyViolation = .midStreamRateDrop(expectedHz: carrierHz, actualHz: actual)
            }

            if let violation = safetyViolation {
                isDopStreamActive = false
                activeDopCarrierHz = nil
                if reason == .oldDeviceUnavailable {
                    pausedForRouteRemoval = true
                    resumeAfterInterruption = false
                    isInterrupted = false
                }
                logger.log(
                    event: "dop-route-safety-halt",
                    category: "safety",
                    message: violation.message,
                    fields: ["code": violation.code, "route": currentRoute.rawValue, "sessionHz": profile.currentSessionSampleRateHz]
                )
                delegate?.sessionDidTriggerDopSafetyViolation(reason: violation)
                delegate?.sessionDidUpdateProfile(profile)
                return
            }
        }

        if reason == .oldDeviceUnavailable {
            // Unplugging wired DAC/headphones must pause immediately and never inherit stale resume intent.
            pausedForRouteRemoval = true
            resumeAfterInterruption = false
            isInterrupted = false
            delegate?.sessionDidRequestPauseForRouteRemoval(route: currentRoute)
        } else if reason == .newDeviceAvailable {
            delegate?.sessionDidObserveRouteArrival(profile: profile)
        } else if !isDopStreamActive,
                  (isPlayingProvider?() ?? false),
                  !isInterrupted,
                  currentRoute == .usbAudio,
                  let expectedHz = expectedUsbPcmRateHz,
                  (profile.currentSessionSampleRateHz != expectedHz ||
                   (profile.bassDeviceSampleRateHz > 0 && profile.bassDeviceSampleRateHz != expectedHz)) {
            logger.log(
                event: "dac-unexpected-rate-drop",
                category: "dac",
                message: "Unexpected USB PCM rate drift during playback: expected \(expectedHz) Hz, observed session=\(profile.currentSessionSampleRateHz) Hz / BASS=\(profile.bassDeviceSampleRateHz) Hz",
                fields: [
                    "expectedHz": expectedHz,
                    "sessionHz": profile.currentSessionSampleRateHz,
                    "bassHz": profile.bassDeviceSampleRateHz,
                    "categoryOptionsRaw": Int(adapter.categoryOptions.rawValue),
                    "reasonText": Self.describe(reason: reason),
                ]
            )
            delegate?.sessionDidDetectUnexpectedUsbRateDrop(
                expectedHz: expectedHz,
                actualSessionHz: profile.currentSessionSampleRateHz,
                actualBassHz: profile.bassDeviceSampleRateHz
            )
        }

        delegate?.sessionDidUpdateProfile(profile)
    }

    @objc func handleInterruption(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return
        }

        switch type {
        case .began:
            let wasPlaying = isPlayingProvider?() ?? false
            if !isInterrupted {
                resumeAfterInterruption = !pausedForRouteRemoval && wasPlaying
                userIntervenedDuringInterruption = false
            }
            isInterrupted = true
            logger.log(
                event: "interruption-began",
                category: "session",
                message: "Interruption began (wasPlaying=\(wasPlaying), willResume=\(resumeAfterInterruption))",
                fields: [
                    "wasPlaying": wasPlaying,
                    "pausedForRouteRemoval": pausedForRouteRemoval,
                    "willResume": resumeAfterInterruption,
                ]
            )
            delegate?.sessionDidBeginInterruption(wasPlaying: wasPlaying)

        case .ended:
            let optionsRaw = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            let iosShouldResume = options.contains(.shouldResume)
            let canResume = !pausedForRouteRemoval && isInterrupted && resumeAfterInterruption && iosShouldResume && !userIntervenedDuringInterruption

            isInterrupted = false
            resumeAfterInterruption = false
            userIntervenedDuringInterruption = false

            logger.log(
                event: "interruption-ended",
                category: "session",
                message: "Interruption ended (iOS.shouldResume=\(iosShouldResume), canResume=\(canResume))",
                fields: [
                    "iosShouldResume": iosShouldResume,
                    "canResume": canResume,
                    "pausedForRouteRemoval": pausedForRouteRemoval,
                    "sessionHz": Int(adapter.sampleRate.rounded()),
                ]
            )

            if canResume {
                delegate?.sessionShouldResumeAfterInterruption()
            }

        @unknown default:
            break
        }
    }

    @objc private func handleMediaServicesLost(_ note: Notification) {
        logger.log(event: "media-services-lost", category: "session", message: "iOS media services lost")
        delegate?.sessionDidObserveMediaServicesLost()
    }

    @objc private func handleMediaServicesReset(_ note: Notification) {
        logger.log(event: "media-services-reset", category: "session", message: "iOS media services reset")
        startupConfigured = false
        delegate?.sessionDidObserveMediaServicesReset()
    }

    static func mapPortType(_ port: AVAudioSession.Port?) -> OutputRouteKind {
        guard let port else { return .unknown }
        switch port {
        case .builtInSpeaker: return .speaker
        case .builtInReceiver: return .receiver
        case .headphones, .headsetMic: return .wiredHeadphones
        case .usbAudio: return .usbAudio
        case .bluetoothA2DP: return .bluetoothA2dp
        case .bluetoothLE: return .bluetoothLe
        case .bluetoothHFP: return .bluetoothHfp
        case .airPlay: return .airPlay
        case .HDMI: return .hdmi
        case .lineOut: return .lineOut
        default: return .unknown
        }
    }

    private static func describe(reason: AVAudioSession.RouteChangeReason?) -> String {
        switch reason {
        case .newDeviceAvailable: return "NewDeviceAvailable"
        case .oldDeviceUnavailable: return "OldDeviceUnavailable"
        case .categoryChange: return "CategoryChange"
        case .override: return "Override"
        case .wakeFromSleep: return "WakeFromSleep"
        case .noSuitableRouteForCategory: return "NoSuitableRoute"
        case .routeConfigurationChange: return "RouteConfigChange"
        default: return "Unknown"
        }
    }
}
