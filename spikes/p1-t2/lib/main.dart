import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: AudioProbe()));
}

const suites = <String, List<String>>{
  'FLAC 阶梯': [
    'flac44100.flac', 'flac48000.flac', 'flac88200.flac',
    'flac96000.flac', 'flac176400.flac', 'flac192000.flac',
  ],
  '混合规格': [
    'flac44100.flac', 'flac96000.flac', 'flac192000.flac',
    'flac48000.flac', 'wav16.wav', 'wav24.wav', 'mono24.wav',
  ],
  '格式与坏文件': [
    'alac96.m4a', 'wav16.wav', 'wav24.wav', 'lossy.mp3', 'lossy.aac',
    'truncated.flac', 'invalid.flac', 'invalid-2.flac', 'short.wav',
    'silence-edge.wav', 'flac44100.flac',
  ],
  '连续参照': ['continuous.wav'],
  '无缝 A → B': ['gap-a.wav', 'gap-b.wav'],
  'DSF': ['dsd64.dsf'],
  '已封装 DoP': ['dop64.wav'],
  '系统控制 / 循环': [
    'flac44100.flac', 'alac96.m4a', 'flac192000.flac', 'lossy.aac',
  ],
};

class AudioProbe extends StatefulWidget {
  const AudioProbe({super.key});

  @override
  State<AudioProbe> createState() => _AudioProbeState();
}

class _AudioProbeState extends State<AudioProbe> with WidgetsBindingObserver {
  static const bridge = MethodChannel('fidelune/p1t2');
  final player = Player(configuration: const PlayerConfiguration(
    title: 'Fidelune P1-T2',
    logLevel: MPVLogLevel.v,
  ));
  final subscriptions = <StreamSubscription<dynamic>>[];
  final assets = <String, File>{};
  late final NativePlayer mpv = player.platform! as NativePlayer;
  late final Timer heartbeat;
  var prepared = false;
  var busy = false;
  var suite = '';
  var gapless = '';
  var requestDop = false;
  var shuffle = false;
  var interrupted = false;
  var resumeAfterInterruption = false;
  var lastInfoSecond = -1;
  var details = '';
  var commandId = 0;
  String? assetDirectory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bridge.setMethodCallHandler(systemEvent);
    subscriptions.addAll([
      player.stream.playlist.listen((_) => refreshState()),
      player.stream.playing.listen((_) => refreshState()),
      player.stream.duration.listen((_) => refreshState()),
      player.stream.position.listen((position) {
        if (lastInfoSecond != position.inSeconds) refreshState();
      }),
      player.stream.error.listen((message) {
        unawaited(record('error', {'message': redact(message), 'track': track}));
      }),
      player.stream.log.listen((log) {
        if (log.prefix.contains('ao') ||
            log.prefix.startsWith('af') ||
            log.text.contains('Opening audio decoder') ||
            log.level == 'error' || log.level == 'warn') {
          unawaited(record('mpv', {
            'prefix': log.prefix, 'level': log.level, 'text': redact(log.text),
          }));
        }
      }),
    ]);
    heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (prepared && suite.isNotEmpty) unawaited(snapshot('heartbeat'));
    });
    unawaited(prepare());
  }

  Future<void> prepare() async {
    try {
      assetDirectory = await bridge.invokeMethod<String>('assetDirectory');
      for (final name in suites.values.expand((names) => names).toSet()) {
        final asset = await rootBundle.load('fixtures/$name');
        final file = File('$assetDirectory/$name');
        await file.writeAsBytes(asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes));
        assets[name] = file;
      }
      for (final property in ['audio-out-params', 'current-ao', 'audio-params', 'path']) {
        await mpv.observeProperty(property, (_) async {
          if (suite.isNotEmpty) await snapshot(property);
        });
      }
      await snapshot('initialized');
      if (mounted) setState(() => prepared = true);
    } catch (error) {
      if (mounted) setState(() => details = redact(error.toString()));
      await record('setup-error', {'message': redact(error.toString())});
    }
  }

  String redact(String value) =>
      assetDirectory == null ? value : value.replaceAll('$assetDirectory/', '');

  String get track {
    final list = player.state.playlist;
    if (list.index < 0 || list.index >= list.medias.length) return '';
    return list.medias[list.index].extras?['name'] as String? ?? '';
  }

  Future<void> record(String event, Map<String, Object?> data) =>
      bridge.invokeMethod<void>('record', {'event': event, 'suite': suite, ...data});

  Future<void> snapshot(String event) async {
    final capturedSuite = suite;
    final pathBefore = await mpv.getProperty('path');
    final fields = <String, Object?>{};
    for (final key in [
      'mpv-version', 'ffmpeg-version', 'current-ao', 'audio-codec-name',
      'audio-params/samplerate', 'audio-params/format', 'audio-params/channels',
      'audio-out-params/samplerate', 'audio-out-params/format',
      'audio-out-params/channels', 'af', 'options/audio-samplerate',
      'options/gapless-audio', 'options/audio-spdif', 'options/audiounit-skip-session-management',
      'volume', 'speed', 'pause', 'time-pos',
    ]) {
      final value = await mpv.getProperty(key);
      fields[key] = value.isEmpty ? null : value;
    }
    final pathAfter = await mpv.getProperty('path');
    final stable = pathBefore == pathAfter && capturedSuite == suite;
    final data = await bridge.invokeMapMethod<String, Object?>('record', {
      'event': event,
      'suite': capturedSuite,
      'path': pathBefore.isEmpty ? null : pathBefore.split('/').last,
      'pathStable': stable,
      'mpv': fields,
      'includeSession': true,
    });
    if (stable && mounted) {
      setState(() => details = [
        fields['mpv-version'],
        '解码 ${fields['audio-params/samplerate'] ?? '未知'} Hz / ${fields['audio-params/format'] ?? '未知'} / ${fields['audio-params/channels'] ?? '未知'}',
        '引擎输出 ${fields['audio-out-params/samplerate'] ?? '未知'} Hz / ${fields['audio-out-params/format'] ?? '未知'} / ${fields['current-ao'] ?? '未知'}',
        '系统会话 ${data?['sampleRateHz'] ?? '未知'} Hz / ${data?['route'] ?? '未知'}',
        'gapless ${fields['options/gapless-audio'] ?? '未知'}',
      ].whereType<String>().join('\n'));
    }
  }

  void refreshState() {
    if (!mounted) return;
    final state = player.state;
    lastInfoSecond = state.position.inSeconds;
    setState(() {});
    unawaited(bridge.invokeMethod<void>('nowPlaying', {
      'track': track,
      'playing': state.playing && !interrupted,
      'position': state.position.inMilliseconds / 1000,
      'duration': state.duration.inMilliseconds / 1000,
    }));
  }

  Future<void> runSuite(String name) async {
    if (!prepared || busy) return;
    setState(() => busy = true);
    try {
      await player.stop();
      suite = name;
      shuffle = false;
      await player.setShuffle(false);
      await player.setPlaylistMode(name == '系统控制 / 循环' ? PlaylistMode.loop : PlaylistMode.none);
      if (gapless.isNotEmpty) await mpv.setProperty('options/gapless-audio', gapless);
      final passthrough = name == 'DSF' && requestDop;
      await mpv.setProperty('options/audio-spdif', passthrough ? 'dsd' : '');
      await record('suite-start', {
        'requestedGapless': gapless.isEmpty ? null : gapless,
        'requestedDsdPassthrough': passthrough,
        'tracks': suites[name],
      });
      final media = suites[name]!.map((file) => Media(
        assets[file]!.uri.toFilePath(), extras: {'name': file},
      )).toList();
      await player.open(Playlist(media));
    } catch (error) {
      await record('suite-error', {'message': redact(error.toString())});
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> command(String action, {String origin = 'app', double? seconds}) async {
    final id = ++commandId;
    if (interrupted && action != 'mark') resumeAfterInterruption = false;
    await record('command', {'id': id, 'origin': origin, 'action': action, 'seconds': seconds, 'track': track});
    switch (action) {
      case 'play': await player.play();
      case 'pause': await player.pause();
      case 'toggle': await player.playOrPause();
      case 'next': await player.next();
      case 'previous': await player.previous();
      case 'seek':
        final at = (seconds ?? player.state.duration.inMilliseconds / 2000)
            .clamp(0, player.state.duration.inMilliseconds / 1000);
        await player.seek(Duration(milliseconds: (at * 1000).round()));
      case 'shuffle':
        shuffle = !shuffle;
        await player.setShuffle(shuffle);
      case 'stop':
        await player.stop();
        suite = '';
      case 'mark': break;
    }
    await record('command-returned', {'id': id, 'track': track});
    unawaited(snapshot('after-$action'));
  }

  Future<void> systemEvent(MethodCall call) async {
    if (!prepared || suite.isEmpty) return;
    final data = Map<String, Object?>.from(call.arguments as Map);
    switch (call.method) {
      case 'remote':
        await command(data['command'] as String, origin: 'system', seconds: (data['seconds'] as num?)?.toDouble());
      case 'unplug':
        resumeAfterInterruption = false;
        await player.pause();
        await snapshot('paused-on-unplug');
      case 'interruption':
        if (data['began'] == true) {
          if (!interrupted) resumeAfterInterruption = player.state.playing;
          interrupted = true;
          await player.pause();
        } else {
          final resume = interrupted && resumeAfterInterruption && data['resume'] == true;
          interrupted = false;
          resumeAfterInterruption = false;
          if (resume) {
            await bridge.invokeMethod<void>('reactivate');
            if (!interrupted) await player.play();
          }
        }
        refreshState();
        await snapshot('interruption-handled');
      case 'route':
        await snapshot('route-notification');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (prepared) unawaited(snapshot('lifecycle-${state.name}'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    bridge.setMethodCallHandler(null);
    heartbeat.cancel();
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = player.state;
    return Scaffold(
      appBar: AppBar(title: const Text('Fidelune P1-T2')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(prepared ? (track.isEmpty ? '选择测试组' : track) : '正在准备合成样本'),
        Text('${state.playing ? '正在播放' : '暂停 / 停止'}  ${state.position.inSeconds} / ${state.duration.inSeconds} 秒'),
        Text(details),
        Wrap(spacing: 8, children: [
          for (final name in suites.keys)
            OutlinedButton(onPressed: prepared && !busy ? () => runSuite(name) : null, child: Text(name)),
        ]),
        Wrap(spacing: 8, children: [
          for (final entry in {
            'previous': '上一首', 'next': '下一首', 'toggle': '播放 / 暂停',
            'seek': '跳到中点', 'shuffle': shuffle ? '关闭随机' : '随机',
            'stop': '停止', 'mark': '记取证点',
          }.entries)
            TextButton(onPressed: prepared && suite.isNotEmpty && !busy ? () => command(entry.key) : null, child: Text(entry.value)),
        ]),
        DropdownButton<String>(
          value: gapless,
          items: const [
            DropdownMenuItem(value: '', child: Text('gapless 原版默认')),
            DropdownMenuItem(value: 'weak', child: Text('gapless weak')),
            DropdownMenuItem(value: 'yes', child: Text('gapless yes 对照')),
            DropdownMenuItem(value: 'no', child: Text('gapless no 对照')),
          ],
          onChanged: !prepared || busy ? null : (value) {
            setState(() => gapless = value!);
            if (value!.isEmpty) unawaited(mpv.setProperty('options/gapless-audio', 'weak'));
          },
        ),
        SwitchListTile(
          title: const Text('下次 DSF 请求 DSD 直通'),
          value: requestDop,
          onChanged: !prepared || busy ? null : (value) => setState(() => requestDop = value),
        ),
        const Text('扬声器或 DAC 先调低音量。DAC 屏幕读数另记。'),
      ]),
    );
  }
}
