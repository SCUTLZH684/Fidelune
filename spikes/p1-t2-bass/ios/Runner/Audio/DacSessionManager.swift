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
}

protocol DacSessionManagerDelegate: AnyObject {
    func sessionDidUpdateProfile(_ profile: DacCapabilityProfile)
    func sessionDidRequestPauseForRouteRemoval(route: OutputRouteKind)
    func sessionDidObserveRouteArrival(profile: DacCapabilityProfile)
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

    /// LyrPlay pattern: activate AVAudioSession ONCE at startup with .playback so Lock Screen
    /// / MPRemoteCommandCenter controls become eligible without manually fighting BASS session hooks.
    func activateAtStartup(modeOption: SessionModeOption = .defaultMode) {
        if !startupConfigured {
            do {
                let avMode: AVAudioSession.Mode = (modeOption == .measurement) ? .measurement : .default
                try adapter.setCategory(.playback, mode: avMode, options: [])
                try adapter.setActive(true, options: [])
                startupConfigured = true
                logger.log(
                    event: "session-startup-activated",
                    category: "session",
                    message: "AVAudioSession startup activation succeeded",
                    fields: [
                        "mode": avMode.rawValue,
                        "sampleRateHz": Int(adapter.sampleRate.rounded()),
                        "route": currentRouteKind().rawValue,
                    ]
                )
            } catch {
                let nsErr = error as NSError
                logger.log(
                    event: "session-startup-error",
                    category: "session",
                    message: "AVAudioSession startup activation failed: \(nsErr.domain) (\(nsErr.code))",
                    fields: ["domain": nsErr.domain, "code": nsErr.code]
                )
            }
        }
        registerObserversIfNeeded()
    }

    func applySessionMode(_ modeOption: SessionModeOption) {
        let desired: AVAudioSession.Mode = (modeOption == .measurement) ? .measurement : .default
        guard adapter.mode != desired else { return }
        do {
            try adapter.setCategory(.playback, mode: desired, options: [])
            logger.log(
                event: "session-mode-changed",
                category: "session",
                message: "AVAudioSession mode changed to \(desired.rawValue)",
                fields: ["mode": desired.rawValue]
            )
        } catch {
            let nsErr = error as NSError
            logger.log(
                event: "session-mode-error",
                category: "session",
                message: "Failed to change AVAudioSession mode: \(nsErr.localizedDescription)",
                fields: ["code": nsErr.code]
            )
        }
    }

    func reactivateSession() {
        do {
            try adapter.setActive(true, options: [])
            logger.log(event: "session-reactivated", category: "session", message: "AVAudioSession reactivated")
        } catch {
            let nsErr = error as NSError
            logger.log(
                event: "session-reactivate-error",
                category: "session",
                message: "AVAudioSession reactivate failed: \(nsErr.domain) (\(nsErr.code))",
                fields: ["code": nsErr.code]
            )
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
        bassReinit: (Int) -> Bool
    ) -> RateNegotiationResult {
        let routeKind = currentRouteKind()
        lastRequestedSampleRateHz = targetHz

        if !routeKind.isWiredDacCapable && routeKind != .wiredHeadphones {
            // Speaker and Bluetooth routes follow system/codec negotiation; record honestly.
            let sessionHz = Int(adapter.sampleRate.rounded())
            let bassHz = bassRateProvider?() ?? 0
            return RateNegotiationResult(
                requestedHz: targetHz,
                sessionActualHz: sessionHz,
                bassDeviceHz: bassHz,
                matchedTarget: sessionHz == targetHz && bassHz == targetHz,
                routeKind: routeKind,
                strategyUsed: strategy,
                settleElapsedMs: 0
            )
        }

        let startTime = Date()
        let initialSessionHz = Int(adapter.sampleRate.rounded())
        let initialBassHz = bassRateProvider?() ?? 0
        if initialSessionHz == targetHz && initialBassHz == targetHz {
            recordProbedRate(targetHz)
            return RateNegotiationResult(
                requestedHz: targetHz,
                sessionActualHz: initialSessionHz,
                bassDeviceHz: initialBassHz,
                matchedTarget: true,
                routeKind: routeKind,
                strategyUsed: strategy,
                settleElapsedMs: 0
            )
        }

        let clampedSettle = max(0, min(1000, settleDelayMs))

        switch strategy {
        case .sessionPreferred:
            try? adapter.setPreferredSampleRate(Double(targetHz))
            if clampedSettle > 0 {
                sleepFn(TimeInterval(clampedSettle) / 1000.0)
            }
        case .bassReinit:
            _ = bassReinit(targetHz)
            if clampedSettle > 0 {
                sleepFn(TimeInterval(clampedSettle) / 1000.0)
            }
        case .hybrid:
            try? adapter.setPreferredSampleRate(Double(targetHz))
            let firstHalfMs = max(30, clampedSettle / 2)
            if clampedSettle > 0 {
                sleepFn(TimeInterval(firstHalfMs) / 1000.0)
            }
            let midSessionHz = Int(adapter.sampleRate.rounded())
            let midBassHz = bassRateProvider?() ?? 0
            if midBassHz != targetHz || midSessionHz != targetHz {
                _ = bassReinit(targetHz)
            }
            let remainingMs = max(0, clampedSettle - firstHalfMs)
            if remainingMs > 0 {
                sleepFn(TimeInterval(remainingMs) / 1000.0)
            }
        }

        let finalSessionHz = Int(adapter.sampleRate.rounded())
        let finalBassHz = bassRateProvider?() ?? 0
        let matched = (finalSessionHz == targetHz) && (finalBassHz == targetHz)
        if matched {
            recordProbedRate(targetHz)
        }
        let elapsedMs = Int((Date().timeIntervalSince(startTime) * 1000.0).rounded())

        logger.log(
            event: "dac-rate-negotiated",
            category: "dac",
            message: "Requested \(targetHz) Hz -> session \(finalSessionHz) Hz, BASS \(finalBassHz) Hz (\(strategy.rawValue))",
            fields: [
                "requestedHz": targetHz,
                "sessionActualHz": finalSessionHz,
                "bassDeviceHz": finalBassHz,
                "matchedTarget": matched,
                "route": routeKind.rawValue,
                "strategy": strategy.rawValue,
                "settleElapsedMs": elapsedMs,
            ]
        )

        let profile = currentProfile()
        delegate?.sessionDidUpdateProfile(profile)

        return RateNegotiationResult(
            requestedHz: targetHz,
            sessionActualHz: finalSessionHz,
            bassDeviceHz: finalBassHz,
            matchedTarget: matched,
            routeKind: routeKind,
            strategyUsed: strategy,
            settleElapsedMs: elapsedMs
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
            ]
        )

        if reason == .oldDeviceUnavailable {
            // Unplugging wired DAC/headphones must pause immediately and never inherit stale resume intent.
            pausedForRouteRemoval = true
            resumeAfterInterruption = false
            isInterrupted = false
            delegate?.sessionDidRequestPauseForRouteRemoval(route: currentRoute)
        } else if reason == .newDeviceAvailable {
            delegate?.sessionDidObserveRouteArrival(profile: profile)
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
