import 'package:flutter/material.dart';
import '../audio/audio_engine_gateway.dart';
import '../models/audio_models.dart';
import '../theme/fidelune_theme.dart';
import '../widgets/signal_path_card.dart';

class DacMonitorScreen extends StatefulWidget {
  const DacMonitorScreen({
    super.key,
    required this.gateway,
    required this.state,
  });

  final AudioEngineGateway gateway;
  final PlaybackStateSnapshot state;

  @override
  State<DacMonitorScreen> createState() => _DacMonitorScreenState();
}

class _DacMonitorScreenState extends State<DacMonitorScreen> {
  static const _probeRates = [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000];
  DacProbeResult? _lastProbe;
  bool _probing = false;

  Future<void> _probe(int hz) async {
    setState(() => _probing = true);
    try {
      final res = await widget.gateway.probeDacSampleRate(hz);
      if (mounted) {
        setState(() => _lastProbe = res);
      }
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dac = widget.state.dacProfile;
    final settings = widget.state.settings;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        SignalPathCard(snapshot: widget.state.signalPath),
        const SizedBox(height: 12),

        // DAC Hardware & Session Capability Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('当前输出设备与 DAC 能力读数', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _kv('设备名称', '${dac.deviceName} (${dac.portType})'),
                _kv('USB DAC 状态', dac.isUsbDac ? '已识别 USB Audio 设备' : '非 USB 设备'),
                _kv('系统会话采样率', '${formatHz(dac.currentSessionSampleRateHz)} (偏好 ${formatHz(dac.preferredSampleRateHz)})'),
                _kv('BASS 设备采样率', formatHz(dac.bassDeviceSampleRateHz)),
                _kv('通道与缓冲', '${dac.outputChannels}/${dac.maxOutputChannels} ch · IO ${dac.ioBufferDurationMs.toStringAsFixed(2)} ms · 延迟 ${dac.outputLatencyMs.toStringAsFixed(1)} ms'),
                _kv('系统输出音量', '${(dac.outputVolume * 100).round()}%${dac.outputVolume >= 0.999 ? ' (满足 DoP 要求)' : ' (未满格，禁止 DoP)'}'),
                _kv('已实测匹配采样率', dac.probedSupportedRatesHz.isEmpty ? '暂未记录' : dac.probedSupportedRatesHz.map(formatHz).join(', ')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Interactive Rate Probe Grid
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('单频点 DAC 采样率握手探测', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                  '独立探测外接 DAC 是否支持指定采样率，不会发声。',
                  style: TextStyle(fontSize: 12, color: FideluneColors.textSecondary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _probeRates.map((hz) {
                    final supported = dac.probedSupportedRatesHz.contains(hz);
                    return OutlinedButton(
                      onPressed: _probing ? null : () => _probe(hz),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: supported ? FideluneColors.emerald : FideluneColors.border,
                        ),
                      ),
                      child: Text(formatHz(hz)),
                    );
                  }).toList(),
                ),
                if (_lastProbe != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '最近探测: 请求 ${formatHz(_lastProbe!.requestedHz)} → 会话 ${formatHz(_lastProbe!.sessionActualHz)} / BASS ${formatHz(_lastProbe!.bassDeviceHz)} (${_lastProbe!.matchedTarget ? '匹配' : '未匹配'}, ${_lastProbe!.settleElapsedMs} ms)',
                    style: TextStyle(
                      fontSize: 12,
                      color: _lastProbe!.matchedTarget ? FideluneColors.emerald : FideluneColors.amber,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Engine & Anti-pop Tuning Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('采样率协商与防爆音参数', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('采样率切换策略', style: TextStyle(fontSize: 12, color: FideluneColors.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: RateSwitchStrategy.values.map((st) {
                    return ChoiceChip(
                      label: Text(st.label, style: const TextStyle(fontSize: 12)),
                      selected: settings.rateSwitchStrategy == st,
                      onSelected: (_) => widget.gateway.updateSettings(settings.copyWith(rateSwitchStrategy: st)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                const Text('AVAudioSession 模式', style: TextStyle(fontSize: 12, color: FideluneColors.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: SessionModeOption.values.map((m) {
                    return ChoiceChip(
                      label: Text(m.label, style: const TextStyle(fontSize: 12)),
                      selected: settings.sessionMode == m,
                      onSelected: (_) => widget.gateway.updateSettings(settings.copyWith(sessionMode: m)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                _SliderRow(
                  label: '跨规格 DAC 锁相稳定间隔',
                  valueLabel: '${settings.dacSettleDelayMs} ms',
                  value: settings.dacSettleDelayMs.toDouble(),
                  min: 0,
                  max: 400,
                  divisions: 8,
                  onChanged: (v) => widget.gateway.updateSettings(settings.copyWith(dacSettleDelayMs: v.round())),
                ),
                _SliderRow(
                  label: 'PCM 暂停/Seek/手动切歌微淡出',
                  valueLabel: '${settings.pcmFadeMs} ms',
                  value: settings.pcmFadeMs.toDouble(),
                  min: 0,
                  max: 40,
                  divisions: 8,
                  onChanged: (v) => widget.gateway.updateSettings(settings.copyWith(pcmFadeMs: v.round())),
                ),
                _SliderRow(
                  label: 'DoP 前置 0x69 静音保护帧',
                  valueLabel: '${settings.dopSilenceLeadMs} ms',
                  value: settings.dopSilenceLeadMs.toDouble(),
                  min: 20,
                  max: 300,
                  divisions: 14,
                  onChanged: (v) => widget.gateway.updateSettings(settings.copyWith(dopSilenceLeadMs: v.round())),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('严格保留自然起播首采样点 (BASS_ATTRIB_NORAMP)', style: TextStyle(fontSize: 13)),
                  value: settings.strictBitPerfectNoRampIn,
                  onChanged: (v) => widget.gateway.updateSettings(settings.copyWith(strictBitPerfectNoRampIn: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('记忆上次精确播放秒数', style: TextStyle(fontSize: 13)),
                  value: settings.rememberExactPosition,
                  onChanged: (v) => widget.gateway.updateSettings(settings.copyWith(rememberExactPosition: v)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(k, style: const TextStyle(fontSize: 12.5, color: FideluneColors.textSecondary)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
            Text(valueLabel, style: const TextStyle(fontSize: 12.5, color: FideluneColors.sky)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
