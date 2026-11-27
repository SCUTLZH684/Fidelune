import 'package:flutter/material.dart';
import '../acceptance/acceptance_catalog.dart';
import '../acceptance/acceptance_controller.dart';
import '../audio/audio_engine_gateway.dart';
import '../models/audio_models.dart';
import '../theme/fidelune_theme.dart';
import '../widgets/signal_path_card.dart';
import 'test_item_detail_screen.dart';

class AcceptanceHomeScreen extends StatefulWidget {
  const AcceptanceHomeScreen({
    super.key,
    required this.gateway,
    required this.controller,
    required this.state,
    required this.tracksByName,
  });

  final AudioEngineGateway gateway;
  final AcceptanceController controller;
  final PlaybackStateSnapshot state;
  final Map<String, TrackSpec> tracksByName;

  @override
  State<AcceptanceHomeScreen> createState() => _AcceptanceHomeScreenState();
}

class _AcceptanceHomeScreenState extends State<AcceptanceHomeScreen> {
  bool _expandAutoDetails = false;

  void _openItem(AcceptanceTestItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TestItemDetailScreen(
          initialItem: item,
          initialState: widget.state,
          gateway: widget.gateway,
          controller: widget.controller,
          tracksByName: widget.tracksByName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final nextItem = ctrl.nextPendingItem();
        final dac = widget.state.dacProfile;
        final manualProgress = ctrl.totalManualCount == 0
            ? 0.0
            : ctrl.passedManualCount / ctrl.totalManualCount;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            // Hero Progress & Quick Resume Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'BASS 音频与 DAC 集中验收',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${ctrl.passedManualCount}/${ctrl.totalManualCount} 已通过',
                          style: const TextStyle(
                            color: FideluneColors.emerald,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: manualProgress,
                        minHeight: 8,
                        backgroundColor: FideluneColors.surfaceElevated,
                        valueColor: const AlwaysStoppedAnimation(FideluneColors.emerald),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '当前路由: ${dac.deviceName} (${dac.routeKind}) · 会话 ${formatHz(dac.currentSessionSampleRateHz)} · 音量 ${(dac.outputVolume * 100).round()}%',
                      style: const TextStyle(fontSize: 12.5, color: FideluneColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: ctrl.runningAutoTests ? null : () => ctrl.runAutomatedChecks(),
                          icon: ctrl.runningAutoTests
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.bolt_rounded, size: 18),
                          label: Text(
                            ctrl.runningAutoTests
                                ? '正在运行自动校验...'
                                : (ctrl.totalAutoCount == 0
                                    ? '一键运行 9 项自动校验'
                                    : '重跑自动校验 (${ctrl.passedAutoCount}/${ctrl.totalAutoCount})'),
                          ),
                        ),
                        if (nextItem != null)
                          OutlinedButton.icon(
                            onPressed: () => _openItem(nextItem),
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: Text('继续 ${nextItem.id} · ${nextItem.title.split('：').first}'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Live Signal Path Compact Preview
            SignalPathCard(snapshot: widget.state.signalPath, compact: true),
            const SizedBox(height: 12),

            // Automated Machine Baseline Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _expandAutoDetails = !_expandAutoDetails),
                      child: Row(
                        children: [
                          Icon(
                            ctrl.totalAutoCount > 0 && ctrl.passedAutoCount == ctrl.totalAutoCount
                                ? Icons.verified_rounded
                                : Icons.memory_rounded,
                            color: ctrl.totalAutoCount == 0
                                ? FideluneColors.sky
                                : (ctrl.passedAutoCount == ctrl.totalAutoCount
                                    ? FideluneColors.emerald
                                    : FideluneColors.coral),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '第 0 组 · 机器自动化音频内核校验 (约 3 秒)',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  ctrl.totalAutoCount == 0
                                      ? '涵盖插件加载、24-bit 位精确 SHA-256、0 帧差无缝、DoP 0x05/0xFA 与坏文件容错'
                                      : '已完成 ${ctrl.passedAutoCount}/${ctrl.totalAutoCount} 项通过（点击展开明细）',
                                  style: const TextStyle(fontSize: 12, color: FideluneColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Icon(_expandAutoDetails ? Icons.expand_less : Icons.expand_more),
                        ],
                      ),
                    ),
                    if (_expandAutoDetails && ctrl.autoResults.isNotEmpty) ...[
                      const Divider(height: 18),
                      for (final r in ctrl.autoResults)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                r.passed ? Icons.check_circle : Icons.cancel,
                                size: 16,
                                color: r.passed ? FideluneColors.emerald : FideluneColors.coral,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${r.title} (${r.durationMs} ms)',
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      r.summary,
                                      style: const TextStyle(fontSize: 11.5, color: FideluneColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Categorized Human Acceptance Groups
            for (final group in AcceptanceGroupId.values) ...[
              _GroupSection(
                group: group,
                items: acceptanceCatalog.where((e) => e.group == group).toList(),
                controller: ctrl,
                onTapItem: _openItem,
              ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.items,
    required this.controller,
    required this.onTapItem,
  });

  final AcceptanceGroupId group;
  final List<AcceptanceTestItem> items;
  final AcceptanceController controller;
  final void Function(AcceptanceTestItem) onTapItem;

  @override
  Widget build(BuildContext context) {
    final passedCount =
        items.where((i) => controller.recordFor(i.id).status == TestItemStatus.passed).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '$passedCount/${items.length}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: passedCount == items.length
                        ? FideluneColors.emerald
                        : FideluneColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              group.description,
              style: const TextStyle(fontSize: 12, color: FideluneColors.textSecondary),
            ),
            const SizedBox(height: 10),
            for (final item in items) ...[
              _ItemRow(
                item: item,
                record: controller.recordFor(item.id),
                onTap: () => onTapItem(item),
              ),
              if (item != items.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.record,
    required this.onTap,
  });

  final AcceptanceTestItem item;
  final AcceptanceRecord record;
  final VoidCallback onTap;

  Color _statusColor(TestItemStatus status) {
    switch (status) {
      case TestItemStatus.pending:
        return FideluneColors.textSecondary;
      case TestItemStatus.passed:
        return FideluneColors.emerald;
      case TestItemStatus.failed:
        return FideluneColors.coral;
      case TestItemStatus.skipped:
        return FideluneColors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sColor = _statusColor(record.status);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: FideluneColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: record.status == TestItemStatus.failed
                ? FideluneColors.coral.withValues(alpha: 0.5)
                : FideluneColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.id,
                style: TextStyle(fontWeight: FontWeight.w800, color: sColor, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _MiniTag(item.estimatedTime, FideluneColors.textSecondary),
                      if (item.requiresUsbDac) _MiniTag('需 USB DAC', FideluneColors.sky),
                      if (item.requiresDopSafety) _MiniTag('DoP 安全锁', FideluneColors.amber),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  record.status.label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sColor),
                ),
                if (record.attempts > 0)
                  Text(
                    '已测 ${record.attempts} 次',
                    style: const TextStyle(fontSize: 10.5, color: FideluneColors.textSecondary),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: FideluneColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
