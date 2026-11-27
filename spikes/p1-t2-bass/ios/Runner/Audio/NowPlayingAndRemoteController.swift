import Foundation
import MediaPlayer

protocol RemoteCommandDelegate: AnyObject {
    func remoteDidRequestPlay()
    func remoteDidRequestPause()
    func remoteDidRequestToggle()
    func remoteDidRequestNext()
    func remoteDidRequestPrevious()
    func remoteDidRequestSeek(seconds: Double)
}

final class NowPlayingAndRemoteController {
    weak var delegate: RemoteCommandDelegate?
    private let logger: DiagnosticsSink
    private var commandsRegistered = false
    private var hasActiveTrack = false

    init(logger: DiagnosticsSink = DiagnosticsLogger.shared) {
        self.logger = logger
    }

    func registerRemoteCommands() {
        guard !commandsRegistered else { return }
        commandsRegistered = true

        let center = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand, _ name: String, handler: @escaping (MPRemoteCommandEvent) -> Void) {
            command.removeTarget(nil)
            command.isEnabled = true
            command.addTarget { [weak self] event in
                guard let self, self.hasActiveTrack else { return .noActionableNowPlayingItem }
                DispatchQueue.main.async {
                    self.logger.log(event: "remote-command", category: "remote", message: "Received lock-screen command: \(name)")
                    handler(event)
                }
                return .success
            }
        }

        bind(center.playCommand, "play") { [weak self] _ in self?.delegate?.remoteDidRequestPlay() }
        bind(center.pauseCommand, "pause") { [weak self] _ in self?.delegate?.remoteDidRequestPause() }
        bind(center.togglePlayPauseCommand, "toggle") { [weak self] _ in self?.delegate?.remoteDidRequestToggle() }
        bind(center.nextTrackCommand, "next") { [weak self] _ in self?.delegate?.remoteDidRequestNext() }
        bind(center.previousTrackCommand, "previous") { [weak self] _ in self?.delegate?.remoteDidRequestPrevious() }
        bind(center.changePlaybackPositionCommand, "seek") { [weak self] event in
            if let posEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.delegate?.remoteDidRequestSeek(seconds: posEvent.positionTime)
            }
        }
    }

    func updateNowPlaying(
        track: TrackSpec?,
        isPlaying: Bool,
        positionSeconds: Double,
        durationSeconds: Double,
        signalPath: SignalPathSnapshot
    ) {
        let center = MPNowPlayingInfoCenter.default()
        guard let track else {
            hasActiveTrack = false
            center.nowPlayingInfo = nil
            return
        }

        hasActiveTrack = true
        let rateStr = signalPath.sourceSampleRateHz > 0
            ? String(format: "%.1f kHz", Double(signalPath.sourceSampleRateHz) / 1000.0)
            : ""
        let subtitle = signalPath.dopActive
            ? "DoP · \(signalPath.routeName)"
            : "\(signalPath.sourceCodec) \(rateStr) · \(signalPath.routeName)"

        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: subtitle.trimmingCharacters(in: .whitespaces),
            MPMediaItemPropertyPlaybackDuration: max(0, durationSeconds),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, positionSeconds),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }
}
