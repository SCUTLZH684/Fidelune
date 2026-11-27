import 'dart:async';
import 'package:flutter/material.dart';
import 'acceptance/acceptance_controller.dart';
import 'audio/audio_engine_gateway.dart';
import 'models/audio_models.dart';
import 'screens/acceptance_home_screen.dart';
import 'screens/dac_monitor_screen.dart';
import 'screens/player_library_screen.dart';
import 'screens/report_export_screen.dart';
import 'theme/fidelune_theme.dart';
import 'widgets/mini_player_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FideluneBassApp(gateway: MethodChannelAudioEngineGateway()));
}

class FideluneBassApp extends StatelessWidget {
  const FideluneBassApp({super.key, required this.gateway});

  final AudioEngineGateway gateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fidelune BASS',
      debugShowCheckedModeBanner: false,
      theme: buildFideluneTheme(),
      home: FideluneShell(gateway: gateway),
    );
  }
}

class FideluneShell extends StatefulWidget {
  const FideluneShell({super.key, required this.gateway});

  final AudioEngineGateway gateway;

  @override
  State<FideluneShell> createState() => _FideluneShellState();
}

class _FideluneShellState extends State<FideluneShell> {
  late final AcceptanceController _acceptanceController;

  int _tabIndex = 0;
  bool _ready = false;
  PlaybackStateSnapshot _state = const PlaybackStateSnapshot();
  List<TrackSpec> _bundledTracks = const [];
  List<TrackSpec> _userTracks = const [];
  Map<String, TrackSpec> _tracksByName = const {};
  StreamSubscription<PlaybackStateSnapshot>? _stateSub;
  StreamSubscription<EngineAlert>? _alertSub;

  @override
  void initState() {
    super.initState();
    _acceptanceController = AcceptanceController(widget.gateway);
    _stateSub = widget.gateway.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _alertSub = widget.gateway.alertStream.listen((alert) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(alert.message),
          backgroundColor: alert.code.startsWith('dop_') ? FideluneColors.coral : FideluneColors.surfaceElevated,
        ),
      );
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final res = await widget.gateway.initialize();
    await _acceptanceController.loadPersistedState();
    if (!mounted) return;
    setState(() {
      _ready = true;
      _state = res.state;
      _bundledTracks = res.bundledTracks;
      _userTracks = res.userTracks;
      _tracksByName = {for (final t in res.bundledTracks) t.fileName: t};
    });
  }

  Future<void> _refreshUserTracks() async {
    final user = await widget.gateway.scanUserMusicFolder();
    if (mounted) {
      setState(() => _userTracks = user);
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _alertSub?.cancel();
    _acceptanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      AcceptanceHomeScreen(
        gateway: widget.gateway,
        controller: _acceptanceController,
        state: _state,
        tracksByName: _tracksByName,
      ),
      PlayerLibraryScreen(
        gateway: widget.gateway,
        state: _state,
        bundledTracks: _bundledTracks,
        userTracks: _userTracks,
        onRefreshUserTracks: _refreshUserTracks,
      ),
      DacMonitorScreen(gateway: widget.gateway, state: _state),
      ReportExportScreen(
        gateway: widget.gateway,
        controller: _acceptanceController,
        state: _state,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fidelune BASS 验收与高保真播放'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: _state.dacProfile.isUsbDac
                  ? FideluneColors.emerald.withValues(alpha: 0.2)
                  : FideluneColors.surfaceElevated,
              side: BorderSide(
                color: _state.dacProfile.isUsbDac ? FideluneColors.emerald : FideluneColors.border,
              ),
              label: Text(
                _state.dacProfile.isUsbDac ? 'USB DAC' : _state.dacProfile.routeKind,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: !_ready
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在初始化 BASS 音频引擎与测试音源...'),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(child: IndexedStack(index: _tabIndex, children: screens)),
                MiniPlayerBar(
                  state: _state,
                  gateway: widget.gateway,
                  onTapOpenPlayer: () => setState(() => _tabIndex = 1),
                ),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: '集中验收'),
          NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: '曲库试听'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: '链路/DAC'),
          NavigationDestination(icon: Icon(Icons.summarize_outlined), selectedIcon: Icon(Icons.summarize), label: '报告导出'),
        ],
      ),
    );
  }
}
