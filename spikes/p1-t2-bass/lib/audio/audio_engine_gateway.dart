import 'dart:async';
import 'package:flutter/services.dart';
import '../models/audio_models.dart';

class EngineInitResult {
  const EngineInitResult({
    required this.initialized,
    required this.bundledTracks,
    required this.userTracks,
    required this.state,
  });

  final bool initialized;
  final List<TrackSpec> bundledTracks;
  final List<TrackSpec> userTracks;
  final PlaybackStateSnapshot state;
}

abstract class AudioEngineGateway {
  Stream<PlaybackStateSnapshot> get stateStream;
  Stream<EngineAlert> get alertStream;

  Future<EngineInitResult> initialize();
  Future<List<SelfTestResult>> runAutomatedSelfTests();
  Future<void> playQueue(
    List<TrackSpec> tracks, {
    int startIndex = 0,
    double startPositionSeconds = 0,
    DsdOutputMode? dsdMode,
  });
  Future<void> play();
  Future<void> pause();
  Future<void> togglePlayPause();
  Future<void> stop();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(double seconds);
  Future<void> setPlaybackMode(PlaybackMode mode);
  Future<void> setDsdMode(DsdOutputMode mode);
  Future<void> acknowledgeDopSafety(bool acknowledged);
  Future<void> updateSettings(EngineSettings settings);
  Future<DacProbeResult> probeDacSampleRate(int hz);
  Future<List<DacProbeResult>> runUsbDacRateSweep();
  Future<List<TrackSpec>> scanUserMusicFolder();
  Future<List<DiagnosticEvent>> getRecentLogs({int limit = 200});
  Future<Map<String, String>> exportPcmCaptures();
  Future<String> exportReportAndShare({required String markdown, required String json});
  Future<bool> saveAcceptanceState(String json);
  Future<String?> loadAcceptanceState();
}

class MethodChannelAudioEngineGateway implements AudioEngineGateway {
  static const _method = MethodChannel('fidelune/bass_audio');
  static const _events = EventChannel('fidelune/bass_events');

  final _stateController = StreamController<PlaybackStateSnapshot>.broadcast();
  final _alertController = StreamController<EngineAlert>.broadcast();
  StreamSubscription<dynamic>? _eventSub;

  @override
  Stream<PlaybackStateSnapshot> get stateStream => _stateController.stream;

  @override
  Stream<EngineAlert> get alertStream => _alertController.stream;

  void _ensureListening() {
    _eventSub ??= _events.receiveBroadcastStream().listen((dynamic raw) {
      if (raw is! Map) return;
      final map = raw.cast<String, dynamic>();
      final type = map['type'] as String? ?? '';
      if (type == 'state') {
        final payload = (map['payload'] as Map?)?.cast<String, dynamic>();
        if (payload != null) {
          _stateController.add(PlaybackStateSnapshot.fromMap(payload));
        }
      } else if (type == 'alert') {
        _alertController.add(EngineAlert(
          code: map['code'] as String? ?? 'alert',
          message: map['message'] as String? ?? '',
        ));
      }
    });
  }

  @override
  Future<EngineInitResult> initialize() async {
    _ensureListening();
    final raw = await _method.invokeMapMethod<String, dynamic>('initialize') ?? const {};
    final bundled = ((raw['bundledTracks'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => TrackSpec.fromMap(m.cast<String, dynamic>()))
        .toList();
    final user = ((raw['userTracks'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => TrackSpec.fromMap(m.cast<String, dynamic>()))
        .toList();
    final stateMap = (raw['state'] as Map?)?.cast<String, dynamic>() ?? const {};
    final snapshot = PlaybackStateSnapshot.fromMap(stateMap);
    _stateController.add(snapshot);
    return EngineInitResult(
      initialized: raw['initialized'] as bool? ?? false,
      bundledTracks: bundled,
      userTracks: user,
      state: snapshot,
    );
  }

  @override
  Future<List<SelfTestResult>> runAutomatedSelfTests() async {
    final list = await _method.invokeListMethod<dynamic>('runAutomatedSelfTests') ?? const [];
    return list
        .whereType<Map>()
        .map((m) => SelfTestResult.fromMap(m.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> playQueue(
    List<TrackSpec> tracks, {
    int startIndex = 0,
    double startPositionSeconds = 0,
    DsdOutputMode? dsdMode,
  }) async {
    final raw = await _method.invokeMapMethod<String, dynamic>('playQueue', {
      'tracks': tracks.map((t) => t.toMap()).toList(),
      'startIndex': startIndex,
      'startPositionSeconds': startPositionSeconds,
      if (dsdMode != null) 'dsdMode': dsdMode.name,
    });
    if (raw != null) {
      _stateController.add(PlaybackStateSnapshot.fromMap(raw));
    }
  }

  @override
  Future<void> play() => _method.invokeMethod<void>('play');

  @override
  Future<void> pause() => _method.invokeMethod<void>('pause');

  @override
  Future<void> togglePlayPause() => _method.invokeMethod<void>('togglePlayPause');

  @override
  Future<void> stop() => _method.invokeMethod<void>('stop');

  @override
  Future<void> next() => _method.invokeMethod<void>('next');

  @override
  Future<void> previous() => _method.invokeMethod<void>('previous');

  @override
  Future<void> seek(double seconds) => _method.invokeMethod<void>('seek', {'seconds': seconds});

  @override
  Future<void> setPlaybackMode(PlaybackMode mode) =>
      _method.invokeMethod<void>('setPlaybackMode', {'mode': mode.name});

  @override
  Future<void> setDsdMode(DsdOutputMode mode) =>
      _method.invokeMethod<void>('setDsdMode', {'mode': mode.name});

  @override
  Future<void> acknowledgeDopSafety(bool acknowledged) =>
      _method.invokeMethod<void>('acknowledgeDopSafety', {'acknowledged': acknowledged});

  @override
  Future<void> updateSettings(EngineSettings settings) async {
    final raw = await _method.invokeMapMethod<String, dynamic>('updateSettings', settings.toMap());
    if (raw != null) {
      _stateController.add(PlaybackStateSnapshot.fromMap(raw));
    }
  }

  @override
  Future<DacProbeResult> probeDacSampleRate(int hz) async {
    final raw = await _method.invokeMapMethod<String, dynamic>('probeDacSampleRate', {'hz': hz}) ?? const {};
    return DacProbeResult.fromMap(raw);
  }

  @override
  Future<List<DacProbeResult>> runUsbDacRateSweep() async {
    final list = await _method.invokeListMethod<dynamic>('runUsbDacRateSweep') ?? const [];
    return list
        .whereType<Map>()
        .map((m) => DacProbeResult.fromMap(m.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<TrackSpec>> scanUserMusicFolder() async {
    final list = await _method.invokeListMethod<dynamic>('scanUserMusicFolder') ?? const [];
    return list
        .whereType<Map>()
        .map((m) => TrackSpec.fromMap(m.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<DiagnosticEvent>> getRecentLogs({int limit = 200}) async {
    final list = await _method.invokeListMethod<dynamic>('getRecentLogs', {'limit': limit}) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => DiagnosticEvent.fromMap(m.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<Map<String, String>> exportPcmCaptures() async {
    final raw = await _method.invokeMapMethod<String, dynamic>('exportPcmCaptures') ?? const {};
    return raw.map((k, v) => MapEntry(k, v.toString()));
  }

  @override
  Future<String> exportReportAndShare({required String markdown, required String json}) async {
    return await _method.invokeMethod<String>('exportReportAndShare', {
          'markdown': markdown,
          'json': json,
        }) ??
        '';
  }

  @override
  Future<bool> saveAcceptanceState(String json) async {
    return await _method.invokeMethod<bool>('saveAcceptanceState', {'json': json}) ?? false;
  }

  @override
  Future<String?> loadAcceptanceState() {
    return _method.invokeMethod<String>('loadAcceptanceState');
  }
}
