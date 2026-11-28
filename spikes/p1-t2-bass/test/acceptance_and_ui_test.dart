import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fidelune_bass/acceptance/acceptance_catalog.dart';
import 'package:fidelune_bass/acceptance/acceptance_controller.dart';
import 'package:fidelune_bass/audio/audio_engine_gateway.dart';
import 'package:fidelune_bass/main.dart';
import 'package:fidelune_bass/models/audio_models.dart';
import 'package:fidelune_bass/screens/acceptance_home_screen.dart';
import 'package:fidelune_bass/screens/dac_monitor_screen.dart';
import 'package:fidelune_bass/screens/test_item_detail_screen.dart';
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
  final List<DsdOutputMode?> playQueueDsdModes = [];
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
      id: 'gap-a.wav',
      title: 'gap-a.wav',
      artist: 'Test',
      album: 'WAV',
      filePath: '/tmp/gap-a.wav',
      fileName: 'gap-a.wav',
    ),
    TrackSpec(
      id: 'gap-b.wav',
      title: 'gap-b.wav',
      artist: 'Test',
      album: 'WAV',
      filePath: '/tmp/gap-b.wav',
      fileName: 'gap-b.wav',
    ),
    TrackSpec(
      id: 'continuous.wav',
      title: 'continuous.wav',
      artist: 'Test',
      album: 'WAV',
      filePath: '/tmp/continuous.wav',
      fileName: 'continuous.wav',
    ),
    TrackSpec(
      id: 'flac352800.flac',
      title: 'flac352800.flac',
      artist: 'Test',
      album: 'FLAC',
      filePath: '/tmp/flac352800.flac',
      fileName: 'flac352800.flac',
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
      SelfTestResult(
        id: 'auto_dop_passthrough_integrity',
        title: 'DoP 自定义流零丢帧',
        passed: true,
        durationMs: 25,
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
    playQueueDsdModes.add(dsdMode);
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
      settleElapsedMs: 80,
      phaseReached: 'phase2_bassReinit',
    );
  }

  @override
  Future<List<DacProbeResult>> runUsbDacRateSweep() async {
    actions.add('runUsbDacRateSweep');
    return const [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000]
        .map(
          (hz) => DacProbeResult(
            requestedHz: hz,
            sessionActualHz: hz,
            bassDeviceHz: hz,
            matchedTarget: true,
            routeKind: 'USBAudio',
            strategyUsed: 'hybrid',
            settleElapsedMs: 80,
            phaseReached: 'phase2_bassReinit',
          ),
        )
        .toList();
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
  test('AcceptanceController persists T1-T7 state, enforces blocking tags & 352.8k requirement', () async {
    final gateway = FakeAudioEngineGateway();
    final controller = AcceptanceController(gateway);

    expect(controller.nextPendingItem()?.id, 'T1');
    expect(controller.totalManualCount, 7);

    // T2 checklist must include 352800 Hz
    final t2 = acceptanceCatalog.firstWhere((e) => e.id == 'T2');
    expect(t2.dacRateChecklistHz, contains(352800));

    // Blocking defect tag must prevent markResult(..., passed) from producing a passed status
    await controller.markResult(
      itemId: 'T1',
      status: TestItemStatus.passed,
      selectedTags: ['暂停爆音'],
      notes: '故意传 passed 测试拦截',
      routeName: 'Speaker',
    );
    expect(controller.recordFor('T1').status, TestItemStatus.failed);
    expect(controller.passedManualCount, 0);

    // Next pending moves to T2, while failed T1 stays failed until retried cleanly
    expect(controller.nextPendingItem()?.id, 'T2');

    // Retry T1 cleanly with empty tags -> passes
    await controller.markResult(
      itemId: 'T1',
      status: TestItemStatus.passed,
      selectedTags: [],
      notes: '已复测无爆音',
    );
    expect(controller.recordFor('T1').attempts, 2);
    expect(controller.recordFor('T1').status, TestItemStatus.passed);

    // T2 passBlockReason rejects missing 352800 Hz or non-matching frequency
    final partialObs = {
      for (final hz in [44100, 48000, 88200, 96000, 176400, 192000, 384000]) hz: '匹配',
    };
    expect(
      controller.passBlockReason(item: t2, selectedTags: const [], dacRateObservations: partialObs),
      contains('352.8 kHz'),
    );
    final allObs = {...partialObs, 352800: '匹配'};
    expect(
      controller.passBlockReason(item: t2, selectedTags: const [], dacRateObservations: allObs),
      isNull,
    );

    await controller.runAutomatedChecks();
    expect(controller.passedAutoCount, 2);

    // Reload from JSON
    final reloaded = AcceptanceController(gateway);
    await reloaded.loadPersistedState();
    expect(reloaded.recordFor('T1').status, TestItemStatus.passed);
    expect(reloaded.passedAutoCount, 2);
  });

  testWidgets('DopSafetyDialog requires USB DAC + 100% volume + 4 checks incl. headphone disconnect', (tester) async {
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
      const MaterialApp(
        home: Scaffold(body: DopSafetyDialog(key: ValueKey('low-vol-dop'), dacProfile: lowVolUsb)),
      ),
    );
    final unlockFinder = find.widgetWithText(FilledButton, '确认安全并解锁 DoP');
    expect(tester.widget<FilledButton>(unlockFinder).onPressed, isNull);

    // 4 checkboxes checked — still blocked because volume is 80%
    expect(find.byType(CheckboxListTile), findsNWidgets(4));
    for (var i = 0; i < 4; i++) {
      final cb = find.byType(CheckboxListTile).at(i);
      await tester.ensureVisible(cb);
      await tester.tap(cb);
    }
    await tester.pump();
    expect(tester.widget<FilledButton>(unlockFinder).onPressed, isNull);

    // USB DAC + 100% volume + 3 of 4 checkboxes -> still blocked until 4th checkbox is checked
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
      const MaterialApp(
        home: Scaffold(body: DopSafetyDialog(key: ValueKey('full-vol-dop'), dacProfile: fullVolUsb)),
      ),
    );
    for (var i = 0; i < 3; i++) {
      final cb = find.byType(CheckboxListTile).at(i);
      await tester.ensureVisible(cb);
      await tester.tap(cb);
    }
    await tester.pump();
    expect(tester.widget<FilledButton>(unlockFinder).onPressed, isNull);

    final cb4 = find.byType(CheckboxListTile).at(3);
    await tester.ensureVisible(cb4);
    await tester.tap(cb4);
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

  testWidgets('Targeted retest UI enforces blocking-tag lock & T6 explicit DoP low-volume action', (tester) async {
    final gateway = FakeAudioEngineGateway();
    await tester.pumpWidget(FideluneBassApp(gateway: gateway));
    await tester.pumpAndSettle();

    expect(find.text('BASS 定向修复与核心复测 (Build #8)'), findsOneWidget);

    await tester.tap(find.text('一键运行 10 项自动校验'));
    await tester.pumpAndSettle();
    expect(gateway.actions, contains('runAutomatedSelfTests'));

    // Enter T1 detail screen
    final t1Finder = find.text('扬声器防爆音（暂停/拖动/切歌）与同规格 A/B 真无缝');
    final homeScroll = find.descendant(
      of: find.byType(AcceptanceHomeScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(t1Finder, 200, scrollable: homeScroll);
    await tester.pumpAndSettle();
    await tester.tap(t1Finder);
    await tester.pumpAndSettle();

    // T1 Action 1 plays poptest-a -> b (2 tracks)
    final action1Btn = find.text('动作 1：播放防爆音测试 (poptest-a → b)');
    await tester.ensureVisible(action1Btn);
    await tester.tap(action1Btn);
    await tester.pumpAndSettle();
    expect(gateway.actions, contains('playQueue:2'));

    // Selecting a blocking tag disables the "通过并下一项" button
    final detailScroll = find.descendant(
      of: find.byType(TestItemDetailScreen),
      matching: find.byType(Scrollable),
    );
    final passBtn = find.widgetWithText(FilledButton, '通过并下一项');
    final tagFinder = find.text('暂停爆音');

    // First verify Pass button is initially enabled when scrolling to bottom
    await tester.scrollUntilVisible(passBtn, 200, scrollable: detailScroll);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(passBtn).onPressed, isNotNull);

    // Scroll back up to select blocking tag, then scroll down to verify Pass is disabled
    await tester.scrollUntilVisible(tagFinder, -200, scrollable: detailScroll);
    await tester.pumpAndSettle();
    await tester.tap(tagFinder);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(passBtn, 200, scrollable: detailScroll);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(passBtn).onPressed, isNull);

    // Go back, enter T6, verify Scene A explicitly requests DsdOutputMode.dop
    await tester.pageBack();
    await tester.pumpAndSettle();
    final t6Finder = find.text('DoP 全程安全保护闭环（低音量拦截 + 播中降音量熔断 + 扬声器转 PCM）');
    await tester.scrollUntilVisible(t6Finder, 250, scrollable: homeScroll);
    await tester.pumpAndSettle();
    await tester.tap(t6Finder);
    await tester.pumpAndSettle();

    final sceneABtn = find.textContaining('场景 A：验证低音量起播拦截');
    await tester.ensureVisible(sceneABtn);
    await tester.tap(sceneABtn);
    await tester.pumpAndSettle();
    expect(gateway.playQueueDsdModes.last, DsdOutputMode.dop);

    // Verify Monitor tab exposes 8-rate sweep (no raw debug tuning sliders)
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('链路/DAC'));
    await tester.pumpAndSettle();
    final sweepBtn = find.text('一键探测 8 档全阶梯 (44.1 → 384 kHz)');
    final dacScroll = find.descendant(
      of: find.byType(DacMonitorScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(sweepBtn, 200, scrollable: dacScroll);
    await tester.tap(sweepBtn);
    await tester.pumpAndSettle();
    expect(gateway.actions, contains('runUsbDacRateSweep'));
  });
}
