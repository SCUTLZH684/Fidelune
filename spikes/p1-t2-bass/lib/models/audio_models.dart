enum PlaybackMode {
  sequential('顺序播放'),
  repeatAll('列表循环'),
  repeatOne('单曲循环'),
  shuffle('随机播放');

  const PlaybackMode(this.label);
  final String label;

  static PlaybackMode fromWire(String? raw) {
    return PlaybackMode.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => PlaybackMode.sequential,
    );
  }
}

enum DsdOutputMode {
  auto('自动 (USB DAC 优先 DoP)'),
  dop('强制 DoP'),
  pcm('DSD 转 PCM');

  const DsdOutputMode(this.label);
  final String label;

  static DsdOutputMode fromWire(String? raw) {
    return DsdOutputMode.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => DsdOutputMode.auto,
    );
  }
}

enum RateSwitchStrategy {
  hybrid('混合自适应 (推荐)'),
  sessionPreferred('仅 AVAudioSession 请求'),
  bassReinit('强制 BASS_DEVICE_REINIT');

  const RateSwitchStrategy(this.label);
  final String label;

  static RateSwitchStrategy fromWire(String? raw) {
    return RateSwitchStrategy.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => RateSwitchStrategy.hybrid,
    );
  }
}

enum SessionModeOption {
  defaultMode('默认播放 (.default)'),
  measurement('最小干预 (.measurement)');

  const SessionModeOption(this.label);
  final String label;

  static SessionModeOption fromWire(String? raw) {
    return SessionModeOption.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => SessionModeOption.defaultMode,
    );
  }
}

class TrackSpec {
  const TrackSpec({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    required this.fileName,
    this.isBundledFixture = true,
    this.isPrePackagedDopWav = false,
    this.metadata = const {},
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final String fileName;
  final bool isBundledFixture;
  final bool isPrePackagedDopWav;
  final Map<String, dynamic> metadata;

  factory TrackSpec.fromMap(Map<String, dynamic> map) {
    return TrackSpec(
      id: map['id'] as String? ?? (map['fileName'] as String? ?? ''),
      title: map['title'] as String? ?? (map['fileName'] as String? ?? ''),
      artist: map['artist'] as String? ?? 'Fidelune Test Signal',
      album: map['album'] as String? ?? '',
      filePath: map['filePath'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      isBundledFixture: map['isBundledFixture'] as bool? ?? true,
      isPrePackagedDopWav: map['isPrePackagedDopWav'] as bool? ?? false,
      metadata: (map['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'filePath': filePath,
        'fileName': fileName,
        'isBundledFixture': isBundledFixture,
        'isPrePackagedDopWav': isPrePackagedDopWav,
      };
}

class SignalPathSnapshot {
  const SignalPathSnapshot({
    required this.sourceCodec,
    required this.sourceSampleRateHz,
    required this.sourceValidBits,
    required this.sourceChannels,
    required this.sourceIsDsd,
    required this.sourceDsdRateHz,
    required this.enginePipelineMode,
    required this.engineOutputSampleRateHz,
    required this.engineOutputChannels,
    required this.engineFloatPrecision,
    required this.engineVolumeGain,
    required this.mixerFlags,
    required this.gaplessNextTrackQueued,
    required this.gaplessNextTrackName,
    required this.sessionCategory,
    required this.sessionMode,
    required this.sessionRequestedRateHz,
    required this.sessionActualRateHz,
    required this.bassDeviceRateHz,
    required this.routeKind,
    required this.routeName,
    required this.outputVolume,
    required this.resampledBySystem,
    required this.bitPerfectCandidate,
    required this.dopActive,
    required this.hardwareDisplayUnverifiedNote,
    required this.statusSummary,
  });

  final String sourceCodec;
  final int sourceSampleRateHz;
  final int sourceValidBits;
  final int sourceChannels;
  final bool sourceIsDsd;
  final int sourceDsdRateHz;
  final String enginePipelineMode;
  final int engineOutputSampleRateHz;
  final int engineOutputChannels;
  final String engineFloatPrecision;
  final double engineVolumeGain;
  final String mixerFlags;
  final bool gaplessNextTrackQueued;
  final String? gaplessNextTrackName;
  final String sessionCategory;
  final String sessionMode;
  final int sessionRequestedRateHz;
  final int sessionActualRateHz;
  final int bassDeviceRateHz;
  final String routeKind;
  final String routeName;
  final double outputVolume;
  final bool resampledBySystem;
  final bool bitPerfectCandidate;
  final bool dopActive;
  final String hardwareDisplayUnverifiedNote;
  final String statusSummary;

  static const idle = SignalPathSnapshot(
    sourceCodec: '-',
    sourceSampleRateHz: 0,
    sourceValidBits: 0,
    sourceChannels: 0,
    sourceIsDsd: false,
    sourceDsdRateHz: 0,
    enginePipelineMode: '空闲',
    engineOutputSampleRateHz: 0,
    engineOutputChannels: 0,
    engineFloatPrecision: '-',
    engineVolumeGain: 1.0,
    mixerFlags: '-',
    gaplessNextTrackQueued: false,
    gaplessNextTrackName: null,
    sessionCategory: '-',
    sessionMode: '-',
    sessionRequestedRateHz: 0,
    sessionActualRateHz: 0,
    bassDeviceRateHz: 0,
    routeKind: 'Unknown',
    routeName: '未启动',
    outputVolume: 1.0,
    resampledBySystem: false,
    bitPerfectCandidate: false,
    dopActive: false,
    hardwareDisplayUnverifiedNote: 'iOS 无法回读外接 DAC 实际接收位深与 DoP 锁定灯状态，请核对 DAC 屏幕。',
    statusSummary: '就绪',
  );

  factory SignalPathSnapshot.fromMap(Map<String, dynamic>? map) {
    if (map == null) return idle;
    return SignalPathSnapshot(
      sourceCodec: map['sourceCodec'] as String? ?? '-',
      sourceSampleRateHz: (map['sourceSampleRateHz'] as num?)?.toInt() ?? 0,
      sourceValidBits: (map['sourceValidBits'] as num?)?.toInt() ?? 0,
      sourceChannels: (map['sourceChannels'] as num?)?.toInt() ?? 0,
      sourceIsDsd: map['sourceIsDsd'] as bool? ?? false,
      sourceDsdRateHz: (map['sourceDsdRateHz'] as num?)?.toInt() ?? 0,
      enginePipelineMode: map['enginePipelineMode'] as String? ?? '空闲',
      engineOutputSampleRateHz: (map['engineOutputSampleRateHz'] as num?)?.toInt() ?? 0,
      engineOutputChannels: (map['engineOutputChannels'] as num?)?.toInt() ?? 0,
      engineFloatPrecision: map['engineFloatPrecision'] as String? ?? '-',
      engineVolumeGain: (map['engineVolumeGain'] as num?)?.toDouble() ?? 1.0,
      mixerFlags: map['mixerFlags'] as String? ?? '-',
      gaplessNextTrackQueued: map['gaplessNextTrackQueued'] as bool? ?? false,
      gaplessNextTrackName: map['gaplessNextTrackName'] as String?,
      sessionCategory: map['sessionCategory'] as String? ?? '-',
      sessionMode: map['sessionMode'] as String? ?? '-',
      sessionRequestedRateHz: (map['sessionRequestedRateHz'] as num?)?.toInt() ?? 0,
      sessionActualRateHz: (map['sessionActualRateHz'] as num?)?.toInt() ?? 0,
      bassDeviceRateHz: (map['bassDeviceRateHz'] as num?)?.toInt() ?? 0,
      routeKind: map['routeKind'] as String? ?? 'Unknown',
      routeName: map['routeName'] as String? ?? '未知设备',
      outputVolume: (map['outputVolume'] as num?)?.toDouble() ?? 1.0,
      resampledBySystem: map['resampledBySystem'] as bool? ?? false,
      bitPerfectCandidate: map['bitPerfectCandidate'] as bool? ?? false,
      dopActive: map['dopActive'] as bool? ?? false,
      hardwareDisplayUnverifiedNote: map['hardwareDisplayUnverifiedNote'] as String? ?? idle.hardwareDisplayUnverifiedNote,
      statusSummary: map['statusSummary'] as String? ?? '就绪',
    );
  }
}

class DacProfile {
  const DacProfile({
    required this.deviceName,
    required this.portType,
    required this.routeKind,
    required this.isUsbDac,
    required this.currentSessionSampleRateHz,
    required this.preferredSampleRateHz,
    required this.bassDeviceSampleRateHz,
    required this.outputChannels,
    required this.maxOutputChannels,
    required this.outputVolume,
    required this.ioBufferDurationMs,
    required this.outputLatencyMs,
    required this.probedSupportedRatesHz,
    required this.supportsDopCandidate,
  });

  final String deviceName;
  final String portType;
  final String routeKind;
  final bool isUsbDac;
  final int currentSessionSampleRateHz;
  final int preferredSampleRateHz;
  final int bassDeviceSampleRateHz;
  final int outputChannels;
  final int maxOutputChannels;
  final double outputVolume;
  final double ioBufferDurationMs;
  final double outputLatencyMs;
  final List<int> probedSupportedRatesHz;
  final bool supportsDopCandidate;

  static const empty = DacProfile(
    deviceName: '未检测',
    portType: 'none',
    routeKind: 'Unknown',
    isUsbDac: false,
    currentSessionSampleRateHz: 48000,
    preferredSampleRateHz: 0,
    bassDeviceSampleRateHz: 48000,
    outputChannels: 2,
    maxOutputChannels: 2,
    outputVolume: 1.0,
    ioBufferDurationMs: 0,
    outputLatencyMs: 0,
    probedSupportedRatesHz: [],
    supportsDopCandidate: false,
  );

  factory DacProfile.fromMap(Map<String, dynamic>? map) {
    if (map == null) return empty;
    return DacProfile(
      deviceName: map['deviceName'] as String? ?? '未知设备',
      portType: map['portType'] as String? ?? 'none',
      routeKind: map['routeKind'] as String? ?? 'Unknown',
      isUsbDac: map['isUsbDac'] as bool? ?? false,
      currentSessionSampleRateHz: (map['currentSessionSampleRateHz'] as num?)?.toInt() ?? 0,
      preferredSampleRateHz: (map['preferredSampleRateHz'] as num?)?.toInt() ?? 0,
      bassDeviceSampleRateHz: (map['bassDeviceSampleRateHz'] as num?)?.toInt() ?? 0,
      outputChannels: (map['outputChannels'] as num?)?.toInt() ?? 2,
      maxOutputChannels: (map['maxOutputChannels'] as num?)?.toInt() ?? 2,
      outputVolume: (map['outputVolume'] as num?)?.toDouble() ?? 1.0,
      ioBufferDurationMs: (map['ioBufferDurationMs'] as num?)?.toDouble() ?? 0,
      outputLatencyMs: (map['outputLatencyMs'] as num?)?.toDouble() ?? 0,
      probedSupportedRatesHz: ((map['probedSupportedRatesHz'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      supportsDopCandidate: map['supportsDopCandidate'] as bool? ?? false,
    );
  }
}

class EngineSettings {
  const EngineSettings({
    this.rateSwitchStrategy = RateSwitchStrategy.hybrid,
    this.dacSettleDelayMs = 80,
    this.pcmFadeMs = 20,
    this.dopSilenceLeadMs = 100,
    this.dopSilenceTrailMs = 80,
    this.dsdPcmTargetRateHz = 176400,
    this.sessionMode = SessionModeOption.defaultMode,
    this.strictBitPerfectNoRampIn = true,
    this.rememberExactPosition = true,
  });

  final RateSwitchStrategy rateSwitchStrategy;
  final int dacSettleDelayMs;
  final int pcmFadeMs;
  final int dopSilenceLeadMs;
  final int dopSilenceTrailMs;
  final int dsdPcmTargetRateHz;
  final SessionModeOption sessionMode;
  final bool strictBitPerfectNoRampIn;
  final bool rememberExactPosition;

  factory EngineSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const EngineSettings();
    return EngineSettings(
      rateSwitchStrategy: RateSwitchStrategy.fromWire(map['rateSwitchStrategy'] as String?),
      dacSettleDelayMs: (map['dacSettleDelayMs'] as num?)?.toInt() ?? 180,
      pcmFadeMs: (map['pcmFadeMs'] as num?)?.toInt() ?? 15,
      dopSilenceLeadMs: (map['dopSilenceLeadMs'] as num?)?.toInt() ?? 100,
      dopSilenceTrailMs: (map['dopSilenceTrailMs'] as num?)?.toInt() ?? 80,
      dsdPcmTargetRateHz: (map['dsdPcmTargetRateHz'] as num?)?.toInt() ?? 176400,
      sessionMode: SessionModeOption.fromWire(map['sessionMode'] as String?),
      strictBitPerfectNoRampIn: map['strictBitPerfectNoRampIn'] as bool? ?? true,
      rememberExactPosition: map['rememberExactPosition'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'rateSwitchStrategy': rateSwitchStrategy.name,
        'dacSettleDelayMs': dacSettleDelayMs,
        'pcmFadeMs': pcmFadeMs,
        'dopSilenceLeadMs': dopSilenceLeadMs,
        'dopSilenceTrailMs': dopSilenceTrailMs,
        'dsdPcmTargetRateHz': dsdPcmTargetRateHz,
        'sessionMode': sessionMode.name,
        'strictBitPerfectNoRampIn': strictBitPerfectNoRampIn,
        'rememberExactPosition': rememberExactPosition,
      };

  EngineSettings copyWith({
    RateSwitchStrategy? rateSwitchStrategy,
    int? dacSettleDelayMs,
    int? pcmFadeMs,
    int? dopSilenceLeadMs,
    int? dopSilenceTrailMs,
    int? dsdPcmTargetRateHz,
    SessionModeOption? sessionMode,
    bool? strictBitPerfectNoRampIn,
    bool? rememberExactPosition,
  }) {
    return EngineSettings(
      rateSwitchStrategy: rateSwitchStrategy ?? this.rateSwitchStrategy,
      dacSettleDelayMs: dacSettleDelayMs ?? this.dacSettleDelayMs,
      pcmFadeMs: pcmFadeMs ?? this.pcmFadeMs,
      dopSilenceLeadMs: dopSilenceLeadMs ?? this.dopSilenceLeadMs,
      dopSilenceTrailMs: dopSilenceTrailMs ?? this.dopSilenceTrailMs,
      dsdPcmTargetRateHz: dsdPcmTargetRateHz ?? this.dsdPcmTargetRateHz,
      sessionMode: sessionMode ?? this.sessionMode,
      strictBitPerfectNoRampIn: strictBitPerfectNoRampIn ?? this.strictBitPerfectNoRampIn,
      rememberExactPosition: rememberExactPosition ?? this.rememberExactPosition,
    );
  }
}

class PlaybackStateSnapshot {
  const PlaybackStateSnapshot({
    this.isPlaying = false,
    this.isPaused = false,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    this.currentIndex = -1,
    this.queueCount = 0,
    this.playbackMode = PlaybackMode.sequential,
    this.dsdMode = DsdOutputMode.auto,
    this.dopSafetyAcknowledged = false,
    this.currentTrack,
    this.signalPath = SignalPathSnapshot.idle,
    this.dacProfile = DacProfile.empty,
    this.settings = const EngineSettings(),
    this.lastErrorMessage,
  });

  final bool isPlaying;
  final bool isPaused;
  final double positionSeconds;
  final double durationSeconds;
  final int currentIndex;
  final int queueCount;
  final PlaybackMode playbackMode;
  final DsdOutputMode dsdMode;
  final bool dopSafetyAcknowledged;
  final TrackSpec? currentTrack;
  final SignalPathSnapshot signalPath;
  final DacProfile dacProfile;
  final EngineSettings settings;
  final String? lastErrorMessage;

  factory PlaybackStateSnapshot.fromMap(Map<String, dynamic> map) {
    final trackMap = (map['currentTrack'] as Map?)?.cast<String, dynamic>();
    return PlaybackStateSnapshot(
      isPlaying: map['isPlaying'] as bool? ?? false,
      isPaused: map['isPaused'] as bool? ?? false,
      positionSeconds: (map['positionSeconds'] as num?)?.toDouble() ?? 0,
      durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ?? 0,
      currentIndex: (map['currentIndex'] as num?)?.toInt() ?? -1,
      queueCount: (map['queueCount'] as num?)?.toInt() ?? 0,
      playbackMode: PlaybackMode.fromWire(map['playbackMode'] as String?),
      dsdMode: DsdOutputMode.fromWire(map['dsdMode'] as String?),
      dopSafetyAcknowledged: map['dopSafetyAcknowledged'] as bool? ?? false,
      currentTrack: trackMap == null ? null : TrackSpec.fromMap(trackMap),
      signalPath: SignalPathSnapshot.fromMap((map['signalPath'] as Map?)?.cast<String, dynamic>()),
      dacProfile: DacProfile.fromMap((map['dacProfile'] as Map?)?.cast<String, dynamic>()),
      settings: EngineSettings.fromMap((map['settings'] as Map?)?.cast<String, dynamic>()),
      lastErrorMessage: map['lastErrorMessage'] as String?,
    );
  }
}

class SelfTestResult {
  const SelfTestResult({
    required this.id,
    required this.title,
    required this.passed,
    required this.durationMs,
    required this.summary,
    required this.details,
  });

  final String id;
  final String title;
  final bool passed;
  final int durationMs;
  final String summary;
  final Map<String, String> details;

  factory SelfTestResult.fromMap(Map<String, dynamic> map) {
    return SelfTestResult(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      passed: map['passed'] as bool? ?? false,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      summary: map['summary'] as String? ?? '',
      details: ((map['details'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'passed': passed,
        'durationMs': durationMs,
        'summary': summary,
        'details': details,
      };
}

class DacProbeResult {
  const DacProbeResult({
    required this.requestedHz,
    required this.sessionActualHz,
    required this.bassDeviceHz,
    required this.matchedTarget,
    required this.routeKind,
    required this.strategyUsed,
    required this.settleElapsedMs,
    this.phaseReached = '',
  });

  final int requestedHz;
  final int sessionActualHz;
  final int bassDeviceHz;
  final bool matchedTarget;
  final String routeKind;
  final String strategyUsed;
  final int settleElapsedMs;
  final String phaseReached;

  factory DacProbeResult.fromMap(Map<String, dynamic> map) {
    return DacProbeResult(
      requestedHz: (map['requestedHz'] as num?)?.toInt() ?? 0,
      sessionActualHz: (map['sessionActualHz'] as num?)?.toInt() ?? 0,
      bassDeviceHz: (map['bassDeviceHz'] as num?)?.toInt() ?? 0,
      matchedTarget: map['matchedTarget'] as bool? ?? false,
      routeKind: map['routeKind'] as String? ?? 'Unknown',
      strategyUsed: map['strategyUsed'] as String? ?? '',
      settleElapsedMs: (map['settleElapsedMs'] as num?)?.toInt() ?? 0,
      phaseReached: map['phaseReached'] as String? ?? '',
    );
  }
}

class EngineAlert {
  const EngineAlert({required this.code, required this.message});
  final String code;
  final String message;
}

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.timestamp,
    required this.category,
    required this.event,
    required this.message,
    required this.memoryBytes,
  });

  final String timestamp;
  final String category;
  final String event;
  final String message;
  final int memoryBytes;

  factory DiagnosticEvent.fromMap(Map<String, dynamic> map) {
    return DiagnosticEvent(
      timestamp: map['timestamp'] as String? ?? '',
      category: map['category'] as String? ?? '',
      event: map['event'] as String? ?? '',
      message: map['message'] as String? ?? '',
      memoryBytes: (map['memoryBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

String formatHz(int hz) {
  if (hz <= 0) return '-';
  if (hz >= 1000000) {
    final mhz = hz / 1000000.0;
    return '${mhz.toStringAsFixed(4)} MHz';
  }
  final khz = hz / 1000.0;
  return khz == khz.truncateToDouble() ? '${khz.toInt()} kHz' : '${khz.toStringAsFixed(1)} kHz';
}

String formatSeconds(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final m = total ~/ 60;
  final s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
