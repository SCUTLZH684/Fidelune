import AVFoundation
import XCTest
@testable import Runner

private final class MockAudioSessionAdapter: AudioSessionAdapter {
    var category: AVAudioSession.Category = .playback
    var mode: AVAudioSession.Mode = .default
    var sampleRate: Double = 48000
    var preferredSampleRate: Double = 0
    var outputNumberOfChannels: Int = 2
    var maximumOutputNumberOfChannels: Int = 2
    var outputVolume: Float = 1.0
    var ioBufferDuration: TimeInterval = 0.005
    var outputLatency: TimeInterval = 0.002
    var primaryOutputPortType: AVAudioSession.Port? = .builtInSpeaker
    var primaryOutputPortName: String? = "Speaker"
    var primaryOutputPortUID: String? = "speaker-1"

    var preferredRatesRequested: [Double] = []

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        self.category = category
        self.mode = mode
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {}

    func setPreferredSampleRate(_ sampleRate: Double) throws {
        self.preferredSampleRate = sampleRate
        self.preferredRatesRequested.append(sampleRate)
        if primaryOutputPortType == .usbAudio {
            self.sampleRate = sampleRate
        }
    }

    func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {
        self.ioBufferDuration = duration
    }
}

private final class NullDiagnosticsSink: DiagnosticsSink {
    func log(event: String, category: String, message: String, fields: [String: Any]) {}
}

private final class MockAudioBackend: AudioPlaybackBackend {
    weak var delegate: AudioPlaybackBackendDelegate?
    var isPlaying: Bool = false
    var currentPositionSeconds: Double = 0
    var currentDurationSeconds: Double = 10
    var currentBassDeviceRateHz: Int = 48000
    var currentSignalPath: SignalPathSnapshot = .idle

    var startedTracks: [TrackSpec] = []
    var pauseCount = 0
    var resumeCount = 0
    var stopCount = 0
    var emergencyHaltReasons: [String] = []
    var reinitRates: [Int] = []

    func initialize() -> Bool { true }
    func reinitializeDeviceAfterMediaReset() -> Bool { true }
    func reinitializeSampleRate(_ targetHz: Int) -> Bool {
        reinitRates.append(targetHz)
        currentBassDeviceRateHz = targetHz
        return true
    }

    func startPlayback(
        track: TrackSpec,
        nextCompatibleTrack: TrackSpec?,
        startPositionSeconds: Double,
        dsdMode: DsdOutputMode,
        dopSafetyAcknowledged: Bool,
        settings: EngineSettings
    ) {
        startedTracks.append(track)
        isPlaying = true
        currentPositionSeconds = startPositionSeconds
        delegate?.backendDidStartPlaying(track: track, signalPath: .idle)
    }

    func updateQueuedNextTrack(_ nextTrack: TrackSpec?) {}

    func pause(fadeMs: Int, completion: (() -> Void)?) {
        isPlaying = false
        pauseCount += 1
        delegate?.backendDidPause(positionSeconds: currentPositionSeconds)
        completion?()
    }

    func resume(fadeMs: Int, completion: (() -> Void)?) {
        isPlaying = true
        resumeCount += 1
        if let last = startedTracks.last {
            delegate?.backendDidStartPlaying(track: last, signalPath: .idle)
        }
        completion?()
    }

    func stop(immediate: Bool, fadeMs: Int, reason: String?, completion: (() -> Void)?) {
        isPlaying = false
        stopCount += 1
        delegate?.backendDidStop(reason: reason)
        completion?()
    }

    func seek(to seconds: Double, fadeMs: Int, completion: (() -> Void)?) {
        currentPositionSeconds = seconds
        completion?()
    }

    func emergencySafetyHalt(reason: String) {
        isPlaying = false
        emergencyHaltReasons.append(reason)
        delegate?.backendDidStop(reason: reason)
    }
}

final class BassAudioEngineTests: XCTestCase {
    func testGaplessCompatibilityRules() {
        let pcm44Stereo = AudioFormatSignature(
            sampleRateHz: 44100, channels: 2, validBits: 16,
            isDsd: false, dsdRateHz: 0, isDop: false, codecName: "FLAC"
        )
        let pcm44Stereo24 = AudioFormatSignature(
            sampleRateHz: 44100, channels: 2, validBits: 24,
            isDsd: false, dsdRateHz: 0, isDop: false, codecName: "WAV PCM"
        )
        let pcm96Stereo = AudioFormatSignature(
            sampleRateHz: 96000, channels: 2, validBits: 24,
            isDsd: false, dsdRateHz: 0, isDop: false, codecName: "FLAC"
        )
        let pcm44Mono = AudioFormatSignature(
            sampleRateHz: 44100, channels: 1, validBits: 24,
            isDsd: false, dsdRateHz: 0, isDop: false, codecName: "WAV PCM"
        )
        let dop64 = AudioFormatSignature(
            sampleRateHz: 176400, channels: 2, validBits: 1,
            isDsd: true, dsdRateHz: 2_822_400, isDop: true, codecName: "DSF"
        )

        XCTAssertTrue(AudioFormatSignature.isGaplessCompatible(lhs: pcm44Stereo, rhs: pcm44Stereo24))
        XCTAssertFalse(AudioFormatSignature.isGaplessCompatible(lhs: pcm44Stereo, rhs: pcm96Stereo))
        XCTAssertFalse(AudioFormatSignature.isGaplessCompatible(lhs: pcm44Stereo, rhs: pcm44Mono))
        XCTAssertFalse(AudioFormatSignature.isGaplessCompatible(lhs: dop64, rhs: dop64))
        XCTAssertEqual(AudioFormatSignature.dopCarrierHz(forDsdRate: 2_822_400), 176400)
        XCTAssertEqual(AudioFormatSignature.dopCarrierHz(forDsdRate: 5_644_800), 352800)
    }

    func testDopSilenceFrameCodecParity() {
        let f05 = DopFrameCodec.packDopSilenceFloat(marker: 0x05)
        let fFA = DopFrameCodec.packDopSilenceFloat(marker: 0xFA)
        XCTAssertEqual(DopFrameCodec.extractDopMarker(fromFloat: f05), 0x05)
        XCTAssertEqual(DopFrameCodec.extractDopMarker(fromFloat: fFA), 0xFA)
    }

    func testDopSafetyInterlocks() {
        let mockSession = MockAudioSessionAdapter()
        let manager = DacSessionManager(
            adapter: mockSession,
            rawSessionForKVO: nil,
            notificationCenter: NotificationCenter(),
            logger: NullDiagnosticsSink(),
            sleepFn: { _ in }
        )

        // 1. Speaker route rejected
        if case .failure(let err) = manager.validateDopSafety(carrierHz: 176400, userAcknowledged: true) {
            XCTAssertEqual(err, .nonUsbRoute(.speaker))
        } else {
            XCTFail("Expected nonUsbRoute failure on speaker")
        }

        // 2. USB DAC with volume < 100% rejected
        mockSession.primaryOutputPortType = .usbAudio
        mockSession.primaryOutputPortName = "TOPPING DX5 II"
        mockSession.outputVolume = 0.85
        if case .failure(let err) = manager.validateDopSafety(carrierHz: 176400, userAcknowledged: true) {
            XCTAssertEqual(err, .systemVolumeNotFull(Double(mockSession.outputVolume)))
        } else {
            XCTFail("Expected systemVolumeNotFull failure")
        }

        // 3. Volume 100% without acknowledgment rejected
        mockSession.outputVolume = 1.0
        if case .failure(let err) = manager.validateDopSafety(carrierHz: 176400, userAcknowledged: false) {
            XCTAssertEqual(err, .userSafetyNotAcknowledged)
        } else {
            XCTFail("Expected userSafetyNotAcknowledged failure")
        }

        // 4. DSD512 (1411.2 kHz carrier) rejected
        if case .failure(let err) = manager.validateDopSafety(carrierHz: 1_411_200, userAcknowledged: true) {
            XCTAssertEqual(err, .carrierRateUnsupported(1_411_200))
        } else {
            XCTFail("Expected carrierRateUnsupported failure")
        }

        // 5. USB DAC + 100% volume + acknowledged + <=768kHz allowed
        if case .failure(let err) = manager.validateDopSafety(carrierHz: 176400, userAcknowledged: true) {
            XCTFail("Unexpected safety failure: \(err)")
        }
    }

    func testRouteRemovalClearsStaleInterruptionAndPauses() {
        let center = NotificationCenter()
        let mockSession = MockAudioSessionAdapter()
        mockSession.primaryOutputPortType = .usbAudio
        let manager = DacSessionManager(
            adapter: mockSession,
            rawSessionForKVO: nil,
            notificationCenter: center,
            logger: NullDiagnosticsSink(),
            sleepFn: { _ in }
        )
        let backend = MockAudioBackend()
        let nowPlaying = NowPlayingAndRemoteController(logger: NullDiagnosticsSink())
        let coord = PlaybackQueueCoordinator(
            backend: backend,
            sessionManager: manager,
            nowPlaying: nowPlaying,
            logger: NullDiagnosticsSink(),
            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )
        manager.configureBindings(
            bassRateProvider: { backend.currentBassDeviceRateHz },
            isPlayingProvider: { backend.isPlaying }
        )
        _ = coord.initializeEngine()

        let track = TrackSpec(id: "t1", title: "T1", filePath: "/tmp/t1.flac", fileName: "t1.flac")
        coord.playQueue(tracks: [track])
        XCTAssertTrue(coord.isPlaying)

        // Simulate unplug -> must pause and mark pausedForRouteRemoval
        mockSession.primaryOutputPortType = .builtInSpeaker
        center.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]
        )
        XCTAssertEqual(backend.pauseCount, 1)
        XCTAssertTrue(manager.pausedForRouteRemoval)

        // A subsequent interruption end must NOT auto-resume after route removal
        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
            ]
        )
        XCTAssertEqual(backend.resumeCount, 0)
    }

    func testConsecutiveCorruptTracksStopCleanlyWithoutInfiniteLoop() {
        let mockSession = MockAudioSessionAdapter()
        let manager = DacSessionManager(
            adapter: mockSession,
            rawSessionForKVO: nil,
            notificationCenter: NotificationCenter(),
            logger: NullDiagnosticsSink(),
            sleepFn: { _ in }
        )
        let backend = MockAudioBackend()
        let coord = PlaybackQueueCoordinator(
            backend: backend,
            sessionManager: manager,
            nowPlaying: NowPlayingAndRemoteController(logger: NullDiagnosticsSink()),
            logger: NullDiagnosticsSink(),
            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let bad1 = TrackSpec(id: "b1", title: "Bad1", filePath: "/tmp/b1.flac", fileName: "b1.flac")
        let bad2 = TrackSpec(id: "b2", title: "Bad2", filePath: "/tmp/b2.flac", fileName: "b2.flac")
        coord.playQueue(tracks: [bad1, bad2])
        coord.setPlaybackMode(.repeatAll)

        coord.backendDidFailTrack(track: bad1, code: "decode_open_failed", message: "bad1")
        XCTAssertEqual(coord.currentOrderIndex, 1)
        coord.backendDidFailTrack(track: bad2, code: "decode_open_failed", message: "bad2")
        // Should halt cleanly after all tracks failed, NOT loop infinitely under repeatAll
        XCTAssertFalse(coord.isPlaying)
        XCTAssertNotNil(coord.lastErrorMessage)
    }

    func testRealBassSelfTestsAgainstBundledFixtures() throws {
        let fm = FileManager.default
        let candidateDirs = [
            ProcessInfo.processInfo.environment["FIDELUNE_FIXTURES_DIR"].map { URL(fileURLWithPath: $0) },
            Bundle.main.bundleURL.appendingPathComponent("Frameworks/App.framework/flutter_assets/fixtures"),
            Bundle.main.bundleURL.appendingPathComponent("flutter_assets/fixtures"),
        ].compactMap { $0 }

        guard let fixturesDir = candidateDirs.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }) else {
            throw XCTSkip("Fixtures directory not staged in test bundle")
        }

        let sessionMgr = DacSessionManager(logger: NullDiagnosticsSink())
        let engine = BassAudioEngine(sessionManager: sessionMgr, logger: NullDiagnosticsSink())
        XCTAssertTrue(engine.initialize(), "BASS engine failed to initialize in Simulator")

        let runner = BassSelfTestRunner(logger: NullDiagnosticsSink())
        let results = runner.runAll(fixturesDirectory: fixturesDir)
        XCTAssertEqual(results.count, 9)
        for item in results {
            XCTAssertTrue(item.passed, "Self-test \(item.id) failed: \(item.summary) | details=\(item.details)")
        }
    }
}
