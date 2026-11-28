import Foundation
import MediaPlayer
import UIKit

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

    private var lastPublishedTrackId: String?
    private var lastPublishedIsPlaying: Bool?
    private var lastPublishedSubtitle: String = ""
    private var lastPublishedDuration: Double = -1
    private var lastPublishedPosition: Double = 0
    private var lastPublishTime: Date = .distantPast

    init(logger: DiagnosticsSink = DiagnosticsLogger.shared) {
        self.logger = logger
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func registerRemoteCommands() {
        onMain { [weak self] in
            guard let self, !self.commandsRegistered else { return }
            self.commandsRegistered = true

            UIApplication.shared.beginReceivingRemoteControlEvents()
            let center = MPRemoteCommandCenter.shared()
            func bind(_ command: MPRemoteCommand, _ name: String, handler: @escaping (MPRemoteCommandEvent) -> Void) {
                command.removeTarget(nil)
                command.isEnabled = true
                command.addTarget { [weak self] event in
                    guard let self, self.hasActiveTrack else { return .noActionableNowPlayingItem }
                    self.onMain {
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
            self.logger.log(event: "remote-commands-registered", category: "remote", message: "MPRemoteCommandCenter registered on main thread")
        }
    }

    func updateNowPlaying(
        track: TrackSpec?,
        isPlaying: Bool,
        positionSeconds: Double,
        durationSeconds: Double,
        signalPath: SignalPathSnapshot,
        force: Bool = false
    ) {
        onMain { [weak self] in
            guard let self else { return }
            let center = MPNowPlayingInfoCenter.default()
            guard let track else {
                if self.lastPublishedTrackId != nil || force {
                    self.hasActiveTrack = false
                    self.lastPublishedTrackId = nil
                    self.lastPublishedIsPlaying = nil
                    self.lastPublishedSubtitle = ""
                    self.lastPublishedDuration = -1
                    center.nowPlayingInfo = nil
                    center.playbackState = .stopped
                }
                return
            }

            self.hasActiveTrack = true
            let rateStr = signalPath.sourceSampleRateHz > 0
                ? String(format: "%.1f kHz", Double(signalPath.sourceSampleRateHz) / 1000.0)
                : ""
            let subtitle = (signalPath.dopActive
                ? "DoP · \(signalPath.routeName)"
                : "\(signalPath.sourceCodec) \(rateStr) · \(signalPath.routeName)").trimmingCharacters(in: .whitespaces)

            let expectedElapsed: Double = (self.lastPublishedIsPlaying == true)
                ? self.lastPublishedPosition + max(0, Date().timeIntervalSince(self.lastPublishTime))
                : self.lastPublishedPosition
            let unchanged = !force &&
                track.id == self.lastPublishedTrackId &&
                isPlaying == self.lastPublishedIsPlaying &&
                subtitle == self.lastPublishedSubtitle &&
                abs(durationSeconds - self.lastPublishedDuration) < 0.05 &&
                abs(positionSeconds - expectedElapsed) < 1.5
            if unchanged {
                return
            }

            let trackOrStateChanged = (track.id != self.lastPublishedTrackId) || (isPlaying != self.lastPublishedIsPlaying)
            self.lastPublishedTrackId = track.id
            self.lastPublishedIsPlaying = isPlaying
            self.lastPublishedSubtitle = subtitle
            self.lastPublishedDuration = durationSeconds
            self.lastPublishedPosition = max(0, positionSeconds)
            self.lastPublishTime = Date()

            center.nowPlayingInfo = [
                MPMediaItemPropertyTitle: track.title,
                MPMediaItemPropertyArtist: track.artist,
                MPMediaItemPropertyAlbumTitle: subtitle,
                MPMediaItemPropertyPlaybackDuration: max(0, durationSeconds),
                MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, positionSeconds),
                MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            ]
            center.playbackState = isPlaying ? .playing : .paused

            if trackOrStateChanged {
                self.logger.log(
                    event: "now-playing-updated",
                    category: "remote",
                    message: "NowPlaying updated: \(track.title) (\(isPlaying ? "playing" : "paused"), \(subtitle))",
                    fields: ["track": track.fileName, "isPlaying": isPlaying, "subtitle": subtitle]
                )
            }
        }
    }
}
