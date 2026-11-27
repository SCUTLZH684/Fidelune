import 'package:flutter/material.dart';
import '../audio/audio_engine_gateway.dart';
import '../models/audio_models.dart';
import '../theme/fidelune_theme.dart';

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({
    super.key,
    required this.state,
    required this.gateway,
    required this.onTapOpenPlayer,
  });

  final PlaybackStateSnapshot state;
  final AudioEngineGateway gateway;
  final VoidCallback onTapOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final track = state.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final sig = state.signalPath;
    final statusBadge = sig.dopActive
        ? 'DoP ${formatHz(sig.engineOutputSampleRateHz)}'
        : (sig.engineOutputSampleRateHz > 0
            ? '${sig.sourceCodec} ${formatHz(sig.engineOutputSampleRateHz)}'
            : track.fileName);

    return Container(
      decoration: const BoxDecoration(
        color: FideluneColors.surfaceElevated,
        border: Border(top: BorderSide(color: FideluneColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTapOpenPlayer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$statusBadge · ${formatSeconds(state.positionSeconds)} / ${formatSeconds(state.durationSeconds)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: FideluneColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: state.isPlaying ? '暂停' : '继续',
            onPressed: () => gateway.togglePlayPause(),
            icon: Icon(state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          IconButton(
            tooltip: '下一首',
            onPressed: () => gateway.next(),
            icon: const Icon(Icons.skip_next_rounded),
          ),
          IconButton(
            tooltip: '紧急静音停止',
            color: FideluneColors.coral,
            onPressed: () => gateway.stop(),
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
      ),
    );
  }
}
