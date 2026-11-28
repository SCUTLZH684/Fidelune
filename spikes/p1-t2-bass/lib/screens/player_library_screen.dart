import 'package:flutter/material.dart';
import '../audio/audio_engine_gateway.dart';
import '../models/audio_models.dart';
import '../theme/fidelune_theme.dart';
import '../widgets/dop_safety_dialog.dart';

class PlayerLibraryScreen extends StatefulWidget {
  const PlayerLibraryScreen({
    super.key,
    required this.gateway,
    required this.state,
    required this.bundledTracks,
    required this.userTracks,
    required this.onRefreshUserTracks,
  });

  final AudioEngineGateway gateway;
  final PlaybackStateSnapshot state;
  final List<TrackSpec> bundledTracks;
  final List<TrackSpec> userTracks;
  final Future<void> Function() onRefreshUserTracks;

  @override
  State<PlayerLibraryScreen> createState() => _PlayerLibraryScreenState();
}

class _PlayerLibraryScreenState extends State<PlayerLibraryScreen> {
  String _query = '';
  bool _showUserOnly = false;
  double? _dragSeconds;

  Future<void> _playFromList(List<TrackSpec> list, int index) async {
    final target = list[index];
    final ext = target.fileName.toLowerCase();
    final isDsd = ext.endsWith('.dsf') || ext.endsWith('.dff') || target.isPrePackagedDopWav;
    if (isDsd &&
        widget.state.dsdMode == DsdOutputMode.dop &&
        !widget.state.dopSafetyAcknowledged) {
      final ok = await DopSafetyDialog.showAndConfirm(context, widget.state.dacProfile);
      if (!ok) return;
      await widget.gateway.acknowledgeDopSafety(true);
    }
    await widget.gateway.playQueue(list, startIndex: index);
  }

  Future<void> _changeDsdMode(DsdOutputMode mode) async {
    if (mode == DsdOutputMode.dop && !widget.state.dopSafetyAcknowledged) {
      final ok = await DopSafetyDialog.showAndConfirm(context, widget.state.dacProfile);
      if (!ok) return;
      await widget.gateway.acknowledgeDopSafety(true);
    }
    await widget.gateway.setDsdMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    final baseList = _showUserOnly
        ? widget.userTracks
        : [...widget.userTracks, ...widget.bundledTracks];
    final filtered = _query.trim().isEmpty
        ? baseList
        : baseList
            .where((t) =>
                t.title.toLowerCase().contains(_query.toLowerCase()) ||
                t.fileName.toLowerCase().contains(_query.toLowerCase()) ||
                t.album.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        // Transport & Modes Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.state.currentTrack?.title ?? '从下方曲库点选音频播放',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.state.signalPath.statusSummary,
                  style: const TextStyle(fontSize: 12, color: FideluneColors.sky),
                ),
                Slider(
                  value: widget.state.durationSeconds > 0
                      ? (_dragSeconds ?? widget.state.positionSeconds)
                          .clamp(0.0, widget.state.durationSeconds)
                      : 0.0,
                  max: widget.state.durationSeconds > 0 ? widget.state.durationSeconds : 1.0,
                  onChanged: widget.state.durationSeconds > 0
                      ? (v) => setState(() => _dragSeconds = v)
                      : null,
                  onChangeEnd: widget.state.durationSeconds > 0
                      ? (v) async {
                          setState(() => _dragSeconds = null);
                          await widget.gateway.seek(v);
                        }
                      : null,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton.outlined(
                      onPressed: () => widget.gateway.previous(),
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    FilledButton.icon(
                      onPressed: () => widget.gateway.togglePlayPause(),
                      icon: Icon(widget.state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      label: Text(widget.state.isPlaying ? '暂停' : '播放'),
                    ),
                    IconButton.outlined(
                      onPressed: () => widget.gateway.next(),
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                    IconButton.outlined(
                      color: FideluneColors.coral,
                      onPressed: () => widget.gateway.stop(),
                      icon: const Icon(Icons.stop_rounded),
                    ),
                  ],
                ),
                const Divider(height: 20),
                const Text('播放模式', style: TextStyle(fontSize: 12, color: FideluneColors.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: PlaybackMode.values.map((m) {
                    return ChoiceChip(
                      label: Text(m.label, style: const TextStyle(fontSize: 12)),
                      selected: widget.state.playbackMode == m,
                      onSelected: (_) => widget.gateway.setPlaybackMode(m),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                const Text('DSD 输出模式', style: TextStyle(fontSize: 12, color: FideluneColors.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: DsdOutputMode.values.map((m) {
                    return ChoiceChip(
                      label: Text(m.label, style: const TextStyle(fontSize: 12)),
                      selected: widget.state.dsdMode == m,
                      onSelected: (_) => _changeDsdMode(m),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // User Music Folder Tip + Rescan
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_open_rounded, color: FideluneColors.sky),
            title: Text('本地导入曲目 (${widget.userTracks.length} 首)', style: const TextStyle(fontSize: 14)),
            subtitle: const Text(
              '可通过 iOS「文件 → 我的 iPhone → Fidelune BASS → Music」放入您自己的无损/DSD 文件试听',
              style: TextStyle(fontSize: 11.5),
            ),
            trailing: IconButton(
              tooltip: '重新扫描 Music 目录',
              onPressed: widget.onRefreshUserTracks,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '搜索文件名或格式...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('仅自导音乐'),
              selected: _showUserOnly,
              onSelected: (v) => setState(() => _showUserOnly = v),
            ),
          ],
        ),
        const SizedBox(height: 10),

        for (var i = 0; i < filtered.length; i++) ...[
          _TrackTile(
            track: filtered[i],
            active: widget.state.currentTrack?.id == filtered[i].id,
            onTap: () => _playFromList(filtered, i),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.active,
    required this.onTap,
  });

  final TrackSpec track;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rateHz = int.tryParse('${track.metadata['ffprobe_rate_hz'] ?? ''}') ?? 0;
    final bits = track.metadata['source_valid_bits'];
    final specStr = rateHz > 0
        ? '${track.album} · ${formatHz(rateHz)}${bits != null ? ' · $bits-bit' : ''}'
        : track.album;

    return Card(
      color: active ? FideluneColors.sky.withValues(alpha: 0.14) : FideluneColors.surface,
      child: ListTile(
        dense: true,
        leading: Icon(
          active ? Icons.equalizer_rounded : Icons.music_note_rounded,
          color: active ? FideluneColors.sky : FideluneColors.textSecondary,
        ),
        title: Text(track.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        subtitle: Text(specStr, style: const TextStyle(fontSize: 11.5, color: FideluneColors.textSecondary)),
        trailing: Text(
          track.isBundledFixture ? '内置' : '用户',
          style: const TextStyle(fontSize: 11, color: FideluneColors.textSecondary),
        ),
        onTap: onTap,
      ),
    );
  }
}
