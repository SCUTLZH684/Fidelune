import AVFoundation
import Foundation

protocol AudioSessionAdapter: AnyObject {
    var category: AVAudioSession.Category { get }
    var mode: AVAudioSession.Mode { get }
    var categoryOptions: AVAudioSession.CategoryOptions { get }
    var sampleRate: Double { get }
    var preferredSampleRate: Double { get }
    var outputNumberOfChannels: Int { get }
    var maximumOutputNumberOfChannels: Int { get }
    var outputVolume: Float { get }
    var ioBufferDuration: TimeInterval { get }
    var outputLatency: TimeInterval { get }
    var primaryOutputPortType: AVAudioSession.Port? { get }
    var primaryOutputPortName: String? { get }
    var primaryOutputPortUID: String? { get }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
    func setPreferredSampleRate(_ sampleRate: Double) throws
    func setPreferredIOBufferDuration(_ duration: TimeInterval) throws
}

final class SystemAudioSessionAdapter: AudioSessionAdapter {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    var category: AVAudioSession.Category { session.category }
    var mode: AVAudioSession.Mode { session.mode }
    var categoryOptions: AVAudioSession.CategoryOptions { session.categoryOptions }
    var sampleRate: Double { session.sampleRate }
    var preferredSampleRate: Double { session.preferredSampleRate }
    var outputNumberOfChannels: Int { session.outputNumberOfChannels }
    var maximumOutputNumberOfChannels: Int { session.maximumOutputNumberOfChannels }
    var outputVolume: Float { session.outputVolume }
    var ioBufferDuration: TimeInterval { session.ioBufferDuration }
    var outputLatency: TimeInterval { session.outputLatency }
    var primaryOutputPortType: AVAudioSession.Port? { session.currentRoute.outputs.first?.portType }
    var primaryOutputPortName: String? { session.currentRoute.outputs.first?.portName }
    var primaryOutputPortUID: String? { session.currentRoute.outputs.first?.uid }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        try session.setCategory(category, mode: mode, options: options)
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        try session.setActive(active, options: options)
    }

    func setPreferredSampleRate(_ sampleRate: Double) throws {
        try session.setPreferredSampleRate(sampleRate)
    }

    func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {
        try session.setPreferredIOBufferDuration(duration)
    }
}

protocol DiagnosticsSink: AnyObject {
    func log(event: String, category: String, message: String, fields: [String: Any])
}

extension DiagnosticsSink {
    func log(event: String, category: String = "audio", message: String) {
        log(event: event, category: category, message: message, fields: [:])
    }
}

protocol AudioPlaybackBackendDelegate: AnyObject {
    func backendDidStartPlaying(track: TrackSpec, signalPath: SignalPathSnapshot)
    func backendDidPause(positionSeconds: Double)
    func backendDidStop(reason: String?)
    func backendDidAdvanceGaplessly(to track: TrackSpec, signalPath: SignalPathSnapshot)
    func backendDidCompleteTrack(track: TrackSpec)
    func backendDidUpdatePosition(seconds: Double, durationSeconds: Double)
    func backendDidUpdateSignalPath(_ signalPath: SignalPathSnapshot)
    func backendDidFailTrack(track: TrackSpec, code: String, message: String)
}

protocol AudioPlaybackBackend: AnyObject {
    var delegate: AudioPlaybackBackendDelegate? { get set }
    var isPlaying: Bool { get }
    var currentPositionSeconds: Double { get }
    var currentDurationSeconds: Double { get }
    var currentBassDeviceRateHz: Int { get }
    var currentSignalPath: SignalPathSnapshot { get }

    func initialize() -> Bool
    func reinitializeDeviceAfterMediaReset() -> Bool
    func reinitializeSampleRate(_ targetHz: Int) -> Bool
    func startPlayback(
        track: TrackSpec,
        nextCompatibleTrack: TrackSpec?,
        startPositionSeconds: Double,
        dsdMode: DsdOutputMode,
        dopSafetyAcknowledged: Bool,
        settings: EngineSettings
    )
    func updateQueuedNextTrack(_ nextTrack: TrackSpec?)
    func pause(fadeMs: Int, completion: (() -> Void)?)
    func resume(fadeMs: Int, completion: (() -> Void)?)
    func stop(immediate: Bool, fadeMs: Int, reason: String?, completion: (() -> Void)?)
    func seek(to seconds: Double, fadeMs: Int, completion: (() -> Void)?)
    func emergencySafetyHalt(reason: String)
    func recoverUnexpectedUsbRateDrop(expectedHz: Int)
}
