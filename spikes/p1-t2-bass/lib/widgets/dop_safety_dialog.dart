import 'package:flutter/material.dart';
import '../models/audio_models.dart';
import '../theme/fidelune_theme.dart';

class DopSafetyDialog extends StatefulWidget {
  const DopSafetyDialog({
    super.key,
    required this.dacProfile,
  });

  final DacProfile dacProfile;

  static Future<bool> showAndConfirm(BuildContext context, DacProfile dacProfile) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DopSafetyDialog(dacProfile: dacProfile),
    );
    return result == true;
  }

  @override
  State<DopSafetyDialog> createState() => _DopSafetyDialogState();
}

class _DopSafetyDialogState extends State<DopSafetyDialog> {
  bool _headphonesUnplugged = false;
  bool _dacAmpTurnedDown = false;
  bool _iosHeadphoneSafetyDisabled = false;
  bool _iosVolumeFullConfirmed = false;

  bool get _usbConnected => widget.dacProfile.isUsbDac;
  bool get _volumeFull => widget.dacProfile.outputVolume >= 0.999;

  bool get _canProceed =>
      _usbConnected &&
      _volumeFull &&
      _headphonesUnplugged &&
      _dacAmpTurnedDown &&
      _iosHeadphoneSafetyDisabled &&
      _iosVolumeFullConfirmed;

  @override
  Widget build(BuildContext context) {
    final volPct = (widget.dacProfile.outputVolume * 100).round();
    return AlertDialog(
      backgroundColor: FideluneColors.surface,
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: FideluneColors.coral),
          SizedBox(width: 8),
          Expanded(child: Text('DoP 高风险听力与设备安全确认', style: TextStyle(fontSize: 16.5))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'DoP 通过 24-bit PCM 封装 DSD 数据。若系统限幅、音量衰减或 DAC 未识别 DoP，会直接发出全幅高频白噪。请严格按顺序核对全部 4 项：',
              style: TextStyle(fontSize: 12.5, color: FideluneColors.textSecondary),
            ),
            const SizedBox(height: 10),
            _LiveGuardTile(
              ok: _usbConnected,
              label: _usbConnected
                  ? '已连接 USB DAC: ${widget.dacProfile.deviceName}'
                  : '未检测到 USB DAC（当前路由: ${widget.dacProfile.routeKind}）',
            ),
            const SizedBox(height: 6),
            _LiveGuardTile(
              ok: _volumeFull,
              label: _volumeFull
                  ? 'iPhone 系统音量已满格 (100%)'
                  : 'iPhone 系统音量仅 $volPct%，必须先用侧边音量键调至 100%',
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: FideluneColors.coral.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FideluneColors.coral.withValues(alpha: 0.65)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  value: _headphonesUnplugged,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    '1. 我已先从 DAC / 耳放物理拔下耳机（先仅看 DAC 面板确认点亮 DSD，再调最低音量插耳机试听）',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: FideluneColors.coral),
                  ),
                  onChanged: (v) => setState(() => _headphonesUnplugged = v ?? false),
                ),
              ),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _dacAmpTurnedDown,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                '2. 我已将外接 DAC / 耳放物理音量调至安全低位（-40 dB 以下 / ≤ 15%）',
                style: TextStyle(fontSize: 13),
              ),
              onChanged: (v) => setState(() => _dacAmpTurnedDown = v ?? false),
            ),
            CheckboxListTile(
              value: _iosHeadphoneSafetyDisabled,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                '3. 我已在 iPhone「设置 → 声音与触感反馈 → 耳机安全 → USB 音频配件」中将 DAC 设为「其他设备」（禁止 iOS 当耳机限幅）',
                style: TextStyle(fontSize: 13),
              ),
              onChanged: (v) => setState(() => _iosHeadphoneSafetyDisabled = v ?? false),
            ),
            CheckboxListTile(
              value: _iosVolumeFullConfirmed,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                '4. 我已知悉：播放期间若拔线、降频或按低音量键，系统将在 0.1 秒内触发静音熔断',
                style: TextStyle(fontSize: 13),
              ),
              onChanged: (v) => setState(() => _iosVolumeFullConfirmed = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('暂不启用'),
        ),
        FilledButton(
          onPressed: _canProceed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('确认安全并解锁 DoP'),
        ),
      ],
    );
  }
}

class _LiveGuardTile extends StatelessWidget {
  const _LiveGuardTile({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = ok ? FideluneColors.emerald : FideluneColors.coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
