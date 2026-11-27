import 'package:flutter/material.dart';
import '../acceptance/acceptance_controller.dart';
import '../audio/audio_engine_gateway.dart';
import '../models/audio_models.dart';
import '../theme/fidelune_theme.dart';

class ReportExportScreen extends StatefulWidget {
  const ReportExportScreen({
    super.key,
    required this.gateway,
    required this.controller,
    required this.state,
  });

  final AudioEngineGateway gateway;
  final AcceptanceController controller;
  final PlaybackStateSnapshot state;

  @override
  State<ReportExportScreen> createState() => _ReportExportScreenState();
}

class _ReportExportScreenState extends State<ReportExportScreen> {
  List<DiagnosticEvent> _logs = const [];
  bool _loadingLogs = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loadingLogs = true);
    try {
      final list = await widget.gateway.getRecentLogs(limit: 200);
      if (mounted) setState(() => _logs = list.reversed.toList());
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _exportAndShare() async {
    final md = widget.controller.toMarkdownReport(widget.state);
    final jsonStr = widget.controller.toJsonReport(widget.state);
    final path = await widget.gateway.exportReportAndShare(markdown: md, json: jsonStr);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('报告与日志已导出至：$path')),
    );
  }

  Future<void> _exportPcmWavs() async {
    final paths = await widget.gateway.exportPcmCaptures();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导出 ${paths.length} 份 PCM 样值比对 WAV 至应用「文件」目录')),
    );
  }

  Future<void> _confirmReset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FideluneColors.surface,
        title: const Text('重置验收记录？'),
        content: const Text('将清空本地保存的各分项验收结果与备注（不会影响音频文件）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FideluneColors.coral),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await widget.controller.resetAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final shownLogs = _filter.trim().isEmpty
            ? _logs
            : _logs
                .where((e) =>
                    e.event.toLowerCase().contains(_filter.toLowerCase()) ||
                    e.category.toLowerCase().contains(_filter.toLowerCase()) ||
                    e.message.toLowerCase().contains(_filter.toLowerCase()))
                .toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('验收结果汇总与导出', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      '机器自动校验：${ctrl.passedAutoCount}/${ctrl.totalAutoCount} 通过\n'
                      '人工/外设验收：通过 ${ctrl.passedManualCount} · 失败 ${ctrl.failedManualCount} · 已完成 ${ctrl.completedManualCount}/${ctrl.totalManualCount}',
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _exportAndShare,
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('导出验收报告与 JSONL 诊断日志 (分享 / 保存)'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _exportPcmWavs,
                            icon: const Icon(Icons.audio_file_outlined, size: 18),
                            label: const Text('导出 PCM 回读 WAV'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: FideluneColors.coral),
                          onPressed: _confirmReset,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('重置进度'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('实时诊断事件日志', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          tooltip: '刷新日志',
                          onPressed: _loadingLogs ? null : _loadLogs,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                        ),
                      ],
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: '过滤事件（如 dac / dop / route / error）',
                        prefixIcon: Icon(Icons.filter_list),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                    const SizedBox(height: 10),
                    if (shownLogs.isEmpty)
                      const Text('暂无日志事件，点击右上角刷新或运行任意测试项。',
                          style: TextStyle(fontSize: 12, color: FideluneColors.textSecondary))
                    else
                      for (final ev in shownLogs.take(80))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: FideluneColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '[${ev.category}] ${ev.event}',
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: FideluneColors.sky),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${(ev.memoryBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                                      style: const TextStyle(
                                          fontSize: 10.5, color: FideluneColors.textSecondary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(ev.message, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
