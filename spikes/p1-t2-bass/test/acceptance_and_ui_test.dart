import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fidelune_bass/acceptance/acceptance_catalog.dart';
import 'package:fidelune_bass/acceptance/acceptance_controller.dart';
import 'package:fidelune_bass/audio/audio_engine_gateway.dart';
import 'package:fidelune_bass/main.dart';
import 'package:fidelune_bass/models/audio_models.dart';
import 'package:fidelune_bass/widgets/dop_safety_dialog.dart';
import 'package:fidelune_bass/widgets/signal_path_card.dart';

class FakeAudioEngineGateway implements AudioEngineGateway {
  FakeAudioEngineGateway({PlaybackStateSnapshot? initialState})
      : _state = initialState ??
            const PlaybackStateSnapshot(
              dacProfile: DacProfile(
                deviceName: 'Speaker',
                portType: 'Speaker',
                routeKind: 'Speaker',
                isUsbDac: false,
                currentSessionSampleRateHz: 48000,
                preferredSampleRateHz: 0,
                bassDeviceSampleRateHz: 48000,
                outputChannels: 2,
                maxOutputChannels: 2,
                outputVolume: 0.7,
                ioBufferDurationMs: 5,
                outputLatencyMs: 2,
                probedSupportedRatesHz: [],
                supportsDopCandidate: false,
              ),
            );

  final _stateController = StreamController<PlaybackStateSnapshot>.broadcast();
  final _alertController = StreamController<EngineAlert>.broadcast();
  PlaybackStateSnapshot _state;
  String? persistedAcceptanceJson;
  final List<String> actions = [];
  bool dopAcknowledged = false;

  final List<TrackSpec> _fixtures = const [
    TrackSpec(
      id: 'poptest-a.flac',
      title: 'poptest-a.flac',
      artist: 'Test',
      album: 'FLAC',
      filePath: '/tmp/poptest-a.flac',
      fileName: 'poptest-a.flac',
    ),
    TrackSpec(
      id: 'poptest-b.flac',
      title: 'poptest-b.flac',
      artist: 'Test',
      album: 'FLAC',
      filePath: '/tmp/poptest-b.flac',
      fileName: 'poptest-b.flac',
    ),
    TrackSpec(
      id: 'dsd64.dsf',
      title: 'dsd64.dsf',
      artist: 'Test',
      album: 'DSF',
      filePath: '/tmp/dsd64.dsf',
      fileName: 'dsd64.dsf',
    ),
  ];

  @override
  Stream<PlaybackStateSnapshot> get stateStream => _stateController.stream;

  @override
  Stream<EngineAlert> get alertStream => _alertController.stream;

  @override
  Future<EngineInitResult> initialize() async {
    return EngineInitResult(
      initialized: true,
      bundledTracks: _fixtures,
      userTracks: const [],
      state: _state,
    );
  }

  @override
  Future<List<SelfTestResult>> runAutomatedSelfTests() async {
    actions.add('runAutomatedSelfTests');
    return const [
      SelfTestResult(
        id: 'auto_bass_init',
        title: 'BASS 初始化',
        passed: true,
        durationMs: 12,
        summary: 'OK',
        details: {},
      ),
    ];
  }

  @override
  Future<void> playQueue(
    List<TrackSpec> tracks, {
    int startIndex = 0,
    double startPositionSeconds = 0,
    DsdOutputMode? dsdMode,
  }) async {
    actions.add('playQueue:${tracks.length}');
    _state = PlaybackStateSnapshot(
      isPlaying: true,
      durationSeconds: 6,
      currentIndex: startIndex,
      queueCount: tracks.length,
      playbackMode: _state.playbackMode,
      dsdMode: dsdMode ?? _state.dsdMode,
      dopSafetyAcknowledged: dopAcknowledged,
      currentTrack: tracks[startIndex],
      dacProfile: _state.dacProfile,
      settings: _state.settings,
      signalPath: SignalPathSnapshot(
        sourceCodec: 'FLAC',
        sourceSampleRateHz: 48000,
        sourceValidBits: 24,
        sourceChannels: 2,
        sourceIsDsd: false,
        sourceDsdRateHz: 0,
        enginePipelineMode: 'BASSmix',
        engineOutputSampleRateHz: 48000,
        engineOutputChannels: 2,
        engineFloatPrecision: 'Float32',
        engineVolumeGain: 1.0,
        mixerFlags: 'BASS_MIXER_QUEUE',
        gaplessNextTrackQueued: tracks.length > 1,
        gaplessNextTrackName: tracks.length > 1 ? tracks[1].fileName : null,
        sessionCategory: 'Playback',
        sessionMode: 'defaultMode',
        sessionRequestedRateHz: 48000,
        sessionActualRateHz: 48000,
        bassDeviceRateHz: 48000,
        routeKind: _state.dacProfile.routeKind,
        routeName: _state.dacProfile.deviceName,
        outputVolume: _state.dacProfile.outputVolume,
        resampledBySystem: false,
        bitPerfectCandidate: _state.dacProfile.isUsbDac,
        dopActive: false,
        hardwareDisplayUnverifiedNote: SignalPathSnapshot.idle.hardwareDisplayUnverifiedNote,
        statusSummary: '原采样率匹配 48 kHz',
      ),
    );
    _stateController.add(_state);
  }

  @override
  Future<void> play() async => actions.add('play');

  @override
  Future<void> pause() async => actions.add('pause');

  @override
  Future<void> togglePlayPause() async => actions.add('toggle');

  @override
  Future<void> stop() async {
    actions.add('stop');
    _state = PlaybackStateSnapshot(dacProfile: _state.dacProfile);
    _stateController.add(_state);
  }

  @override
  Future<void> next() async => actions.add('next');

  @override
  Future<void> previous() async => actions.add('previous');

  @override
  Future<void> seek(double seconds) async => actions.add('seek:$seconds');

  @override
  Future<void> setPlaybackMode(PlaybackMode mode) async => actions.add('mode:${mode.name}');

  @override
  Future<void> setDsdMode(DsdOutputMode mode) async => actions.add('dsd:${mode.name}');

  @override
  Future<void> acknowledgeDopSafety(bool acknowledged) async {
    dopAcknowledged = acknowledged;
    actions.add('ackDop:$acknowledged');
  }

  @override
  Future<void> updateSettings(EngineSettings settings) async {
    _state = PlaybackStateSnapshot(dacProfile: _state.dacProfile, settings: settings);
    _stateController.add(_state);
  }

  @override
  Future<DacProbeResult> probeDacSampleRate(int hz) async {
    return DacProbeResult(
      requestedHz: hz,
      sessionActualHz: hz,
      bassDeviceHz: hz,
      matchedTarget: true,
      routeKind: 'USBAudio',
      strategyUsed: 'hybrid',
      settleElapsedMs: 180,
    );
  }

  @override
  Future<List<TrackSpec>> scanUserMusicFolder() async => const [];

  @override
  Future<List<DiagnosticEvent>> getRecentLogs({int limit = 200}) async => const [];

  @override
  Future<Map<String, String>> exportPcmCaptures() async => const {'pcm24': '/tmp/bass-pcm24.wav'};

  @override
  Future<String> exportReportAndShare({required String markdown, required String json}) async {
    actions.add('exportReport');
    return '/tmp/export';
  }

  @override
  Future<bool> saveAcceptanceState(String json) async {
    persistedAcceptanceJson = json;
    return true;
  }

  @override
  Future<String?> loadAcceptanceState() async => persistedAcceptanceJson;
}

void main() {
  test('AcceptanceController persists state, supports retry & checkpoint resume', () async {
    final gateway = FakeAudioEngineGateway();
    final controller = AcceptanceController(gateway);

    expect(controller.nextPendingItem()?.id, acceptanceCatalog.first.id);

    await controller.runAutomatedChecks();
    expect(controller.passedAutoCount, 1);

    await controller.markResult(
      itemId: 'H1',
      status: TestItemStatus.failed,
      selectedTags: ['暂停爆音'],
      notes: '第1次测',
      routeName: 'Speaker',
    );
    expect(controller.recordFor('H1').attempts, 1);
    // Still pending H2 next
    expect(controller.nextPendingItem()?.id, 'H2');

    // Retry H1 and pass
    await controller.markResult(itemId: 'H1', status: TestItemStatus.passed, notes: '已修复');
    expect(controller.recordFor('H1').attempts, 2);
    expect(controller.passedManualCount, 1);

    // Reload into fresh controller from saved JSON
    final reloaded = AcceptanceController(gateway);
    await reloaded.loadPersistedState();
    expect(reloaded.recordFor('H1').status, TestItemStatus.passed);
    expect(reloaded.recordFor('H1').attempts, 2);
    expect(reloaded.passedAutoCount, 1);

    final md = reloaded.toMarkdownReport(const PlaybackStateSnapshot());
    expect(md, contains('Fidelune BASS 真机集中验收报告'));
    expect(md, contains('H1'));
  });

  testWidgets('DopSafetyDialog blocks unlock without USB DAC + 100% volume + 3 checks', (tester) async {
    const lowVolUsb = DacProfile(
      deviceName: 'TOPPING DX5 II',
      portType: 'USBAudio',
      routeKind: 'USBAudio',
      isUsbDac: true,
      currentSessionSampleRateHz: 48000,
      preferredSampleRateHz: 0,
      bassDeviceSampleRateHz: 48000,
      outputChannels: 2,
      maxOutputChannels: 2,
      outputVolume: 0.80,
      ioBufferDurationMs: 5,
      outputLatencyMs: 2,
      probedSupportedRatesHz: [],
      supportsDopCandidate: false,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DopSafetyDialog(dacProfile: lowVolUsb))),
    );
    final unlockFinder = find.widgetWithText(FilledButton, '确认安全并解锁 DoP');
    expect(tester.widget<FilledButton>(unlockFinder).onPressed, isNull);

    // Check all 3 boxes — still blocked because volume is 80%
    final checkboxes = find.byType(CheckboxListTile);
    for (var i = 0; i < 3; i++) {
      await tester.tap(checkboxes.at(i));
    }
    await tester.pump();
    expect(tester.widget<FilledButton>(unlockFinder).onPressed, isNull);

    // Now test USB DAC at 100% volume + all 3 boxes checked -> enabled
    const fullVolUsb = DacProfile(
      deviceName: 'TOPPING DX5 II',
      portType: 'USBAudio',
      routeKind: 'USBAudio',
      isUsbDac: true,
      currentSessionSampleRateHz: 176400,
      preferredSampleRateHz: 176400,
      bassDeviceSampleRateHz: 176400,
      outputChannels: 2,
      maxOutputChannels: 2,
      outputVolume: 1.0,
      ioBufferDurationMs: 5,
      outputLatencyMs: 2,
      probedSupportedRatesHz: [176400],
      supportsDopCandidate: true,
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DopSafetyDialog(dacProfile: fullVolUsb))),
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(CheckboxListTile).at(i));
    }
    await tester.pump();
    expect(tester.widget<FilledButton>(unlockFinder).onPressed, isNotNull);
  });

  testWidgets('SignalPathCard honestly flags system resampling & hardware limit', (tester) async {
    const resampledSnap = SignalPathSnapshot(
      sourceCodec: 'FLAC',
      sourceSampleRateHz: 192000,
      sourceValidBits: 24,
      sourceChannels: 2,
      sourceIsDsd: false,
      sourceDsdRateHz: 0,
      enginePipelineMode: 'BASSmix 浮点直通队列',
      engineOutputSampleRateHz: 192000,
      engineOutputChannels: 2,
      engineFloatPrecision: 'Float32',
      engineVolumeGain: 1.0,
      mixerFlags: 'BASS_MIXER_QUEUE',
      gaplessNextTrackQueued: false,
      gaplessNextTrackName: null,
      sessionCategory: 'Playback',
      sessionMode: 'defaultMode',
      sessionRequestedRateHz: 192000,
      sessionActualRateHz: 48000,
      bassDeviceRateHz: 48000,
      routeKind: 'Speaker',
      routeName: 'Speaker',
      outputVolume: 1.0,
      resampledBySystem: true,
      bitPerfectCandidate: false,
      dopActive: false,
      hardwareDisplayUnverifiedNote: 'iOS 无法回读外接 DAC 实际接收位深。',
      statusSummary: '系统发生采样率转换：引擎 192000 Hz → 会话 48000 Hz',
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SignalPathCard(snapshot: resampledSnap))),
    );
    expect(find.text('系统重采样'), findsOneWidget);
    expect(find.textContaining('系统不可读'), findsOneWidget);
  });

  testWidgets('FideluneBassApp navigates tabs, runs auto checks, and records H1 pass', (tester) async {
    final gateway = FakeAudioEngineGateway();
    await tester.pumpWidget(FideluneBassApp(gateway: gateway));
    await tester.pumpAndSettle();

    expect(find.text('BASS 音频与 DAC 集中验收'), findsOneWidget);

    await tester.tap(find.text('一键运行 9 项自动校验'));
    await tester.pumpAndSettle();
    expect(gateway.actions, contains('runAutomatedSelfTests'));

    // Enter H1 detail screen
    await tester.tap(find.text('扬声器防爆音：暂停、继续、拖动进度与手动切歌'));
    await tester.pumpAndSettle();
    final launchBtn = find.text('启动本项测试音频 (2 首)');
    await tester.ensureVisible(launchBtn);
    await tester.pumpAndSettle();
    expect(launchBtn, findsOneWidget);

    await tester.tap(launchBtn);
    await tester.pumpAndSettle();
    expect(gateway.actions, contains('playQueue:2'));

    // Switch bottom tabs back on home
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('链路/DAC'));
    await tester.pumpAndSettle();
    expect(find.text('单频点 DAC 采样率握手探测'), findsOneWidget);

    await tester.tap(find.text('报告导出'));
    await tester.pumpAndSettle();
    expect(find.text('验收结果汇总与导出'), findsOneWidget);
  });
}
