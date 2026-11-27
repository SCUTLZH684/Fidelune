import 'package:flutter/material.dart';
import '../models/audio_models.dart';
import '../theme/fidelune_theme.dart';

class SignalPathCard extends StatelessWidget {
  const SignalPathCard({
    super.key,
    required this.snapshot,
    this.compact = false,
  });

  final SignalPathSnapshot snapshot;
  final bool compact;

  Color get _badgeColor {
    if (snapshot.engineOutputSampleRateHz == 0) return FideluneColors.textSecondary;
    if (snapshot.dopActive && snapshot.bitPerfectCandidate) return FideluneColors.emerald;
    if (snapshot.resampledBySystem || !snapshot.bitPerfectCandidate) return FideluneColors.amber;
    return FideluneColors.emerald;
  }

  String get _badgeLabel {
    if (snapshot.engineOutputSampleRateHz == 0) return '空闲';
    if (snapshot.dopActive && snapshot.bitPerfectCandidate) return 'DoP 载波锁定';
    if (snapshot.sourceIsDsd && !snapshot.dopActive) return 'DSD → PCM';
    if (snapshot.resampledBySystem) return '系统重采样';
    if (snapshot.bitPerfectCandidate) return '原采样率直通';
    return '常规系统输出';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.graphic_eq_rounded, color: _badgeColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '实时音频信号链路',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _badgeColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _badgeColor.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    _badgeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              snapshot.statusSummary,
              style: TextStyle(fontSize: 12.5, color: _badgeColor, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            _NodeRow(
              step: '1. 音源解析',
              tag: '只读实测',
              color: FideluneColors.sky,
              value: snapshot.sourceSampleRateHz > 0
                  ? '${snapshot.sourceCodec} · ${formatHz(snapshot.sourceSampleRateHz)} · ${snapshot.sourceValidBits}-bit · ${snapshot.sourceChannels}ch'
                  : '等待播放音源',
            ),
            if (!compact) ...[
              const SizedBox(height: 8),
              _NodeRow(
                step: '2. BASS 引擎',
                tag: '应用观测',
                color: snapshot.dopActive ? FideluneColors.emerald : FideluneColors.sky,
                value: snapshot.engineOutputSampleRateHz > 0
                    ? '${snapshot.enginePipelineMode} (${formatHz(snapshot.engineOutputSampleRateHz)}, 增益 ${snapshot.engineVolumeGain.toStringAsFixed(1)})'
                    : snapshot.enginePipelineMode,
                subtext: snapshot.gaplessNextTrackQueued
                    ? '同规格无缝预排队就绪: ${snapshot.gaplessNextTrackName ?? ''}'
                    : (snapshot.mixerFlags != '-' ? 'Flags: ${snapshot.mixerFlags}' : null),
              ),
            ],
            const SizedBox(height: 8),
            _NodeRow(
              step: compact ? '2. iOS 会话 & 路由' : '3. iOS 会话与设备路由',
              tag: '系统实读',
              color: snapshot.resampledBySystem ? FideluneColors.amber : FideluneColors.emerald,
              value: '${snapshot.routeName} (${snapshot.routeKind}) · 会话 ${formatHz(snapshot.sessionActualRateHz)} · BASS设备 ${formatHz(snapshot.bassDeviceRateHz)}',
              subtext: '请求 ${formatHz(snapshot.sessionRequestedRateHz)} · 音量 ${(snapshot.outputVolume * 100).round()}%',
            ),
            if (!compact) ...[
              const SizedBox(height: 8),
              _NodeRow(
                step: '4. 外接 DAC 物理端',
                tag: '系统不可读',
                color: FideluneColors.textSecondary,
                value: '请对照 DX5 II 前面板读数（采样率 / DSD 指示）',
                subtext: snapshot.hardwareDisplayUnverifiedNote,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.step,
    required this.tag,
    required this.color,
    required this.value,
    this.subtext,
  });

  final String step;
  final String tag;
  final Color color;
  final String value;
  final String? subtext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FideluneColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                step,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: FideluneColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                tag,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (subtext != null && subtext!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtext!,
              style: const TextStyle(fontSize: 11.5, color: FideluneColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
