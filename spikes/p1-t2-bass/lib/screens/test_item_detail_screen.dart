import 'dart:async';
import 'package:flutter/material.dart';
import '../acceptance/acceptance_catalog.dart';
import '../acceptance/acceptance_controller.dart';
import '../audio/audio_engine_gateway.dart';
import '../models/audio_models.dart';
import '../theme/fidelune_theme.dart';
import '../widgets/dop_safety_dialog.dart';
import '../widgets/signal_path_card.dart';

class TestItemDetailScreen extends StatefulWidget {
  const TestItemDetailScreen({
    super.key,
    required this.initialItem,
    required this.initialState,
    required this.gateway,
    required this.controller,
    required this.tracksByName,
  });

  final AcceptanceTestItem initialItem;
  final PlaybackStateSnapshot initialState;
  final AudioEngineGateway gateway;
  final AcceptanceController controller;
  final Map<String, TrackSpec> tracksByName;

  @override
  State<TestItemDetailScreen> createState() => _TestItemDetailScreenState();
}

class _TestItemDetailScreenState extends State<TestItemDetailScreen> {
  late AcceptanceTestItem _item;
  late TextEditingController _notesController;
  late Set<String> _selectedTags;
  late Map<int, String> _dacRateObservations;
  PlaybackStateSnapshot _state = const PlaybackStateSnapshot();
  StreamSubscription<PlaybackStateSnapshot>? _stateSub;
  StreamSubscription<EngineAlert>? _alertSub;
  String? _latestAlert;

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    _state = widget.initialState;
    _loadDraftForCurrentItem();
    _stateSub = widget.gateway.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _alertSub = widget.gateway.alertStream.listen((alert) {
      if (mounted) {
        setState(() => _latestAlert = alert.message);
      }
    });
  }

  void _loadDraftForCurrentItem() {
    final rec = widget.controller.recordFor(_item.id);
    _notesController = TextEditingController(text: rec.notes);
    _selectedTags = Set<String>.from(rec.selectedTags);
    _dacRateObservations = Map<int, String>.from(rec.dacRateObservations);
    _latestAlert = null;
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _alertSub?.cancel();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _launchTestAudio() async {
    if (_item.requiresDopSafety) {
      final confirmed = await DopSafetyDialog.showAndConfirm(context, _state.dacProfile);
      if (!confirmed) return;
      await widget.gateway.acknowledgeDopSafety(true);
    }
    final tracks = _item.fixtureFiles
        .map((name) => widget.tracksByName[name])
        .whereType<TrackSpec>()
        .toList();
    if (tracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到本测试所需的内置音源')),
        );
      }
      return;
    }
    await widget.gateway.setPlaybackMode(_item.desiredPlaybackMode);
    await widget.gateway.setDsdMode(_item.desiredDsdMode);
    await widget.gateway.playQueue(tracks, dsdMode: _item.desiredDsdMode);
  }

  Future<void> _saveOutcome(TestItemStatus status, {bool moveNext = false}) async {
    await widget.controller.markResult(
      itemId: _item.id,
      status: status,
      notes: _notesController.text.trim(),
      selectedTags: _selectedTags.toList(),
      dacRateObservations: _dacRateObservations,
      routeName: '${_state.dacProfile.deviceName} (${_state.dacProfile.routeKind})',
    );
    if (!mounted) return;
    if (moveNext) {
      final next = widget.controller.nextPendingItem(afterId: _item.id);
      if (next != null) {
        await widget.gateway.stop();
        if (!mounted) return;
        setState(() {
          _item = next;
          _notesController.dispose();
          _loadDraftForCurrentItem();
        });
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前全部待测项已处理完毕，可前往「报告」页导出！')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_item.id} 已记录为：${status.label}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.controller.recordFor(_item.id);
    final dac = _state.dacProfile;
    final missingUsbWarning = _item.requiresUsbDac && !dac.isUsbDac;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_item.id} · ${_item.group.title}'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${rec.status.label} (${rec.attempts}次)',
                style: const TextStyle(fontSize: 12.5, color: FideluneColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Text(_item.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_item.subtitle, style: const TextStyle(fontSize: 13, color: FideluneColors.textSecondary)),
          const SizedBox(height: 12),

          if (missingUsbWarning)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: FideluneColors.amber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: FideluneColors.amber.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.usb_off_rounded, color: FideluneColors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '本项需要外接 USB DAC（当前路由为 ${dac.deviceName} / ${dac.routeKind}）。请插好 DX5 II 后开始。',
                      style: const TextStyle(fontSize: 12.5, color: FideluneColors.amber),
                    ),
                  ),
                ],
              ),
            ),

          if (_latestAlert != null || _state.lastErrorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: FideluneColors.coral.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: FideluneColors.coral.withValues(alpha: 0.6)),
              ),
              child: Text(
                _latestAlert ?? _state.lastErrorMessage ?? '',
                style: const TextStyle(fontSize: 12.5, color: FideluneColors.coral),
              ),
            ),

          // Step-by-step instructions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('操作引导', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _item.steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${i + 1}. ${_item.steps[i]}',
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _launchTestAudio,
                      icon: const Icon(Icons.play_circle_fill_rounded),
                      label: Text(
                        _item.requiresDopSafety ? '安全确认并启动 DoP 测试' : '启动本项测试音频 (${_item.fixtureFiles.length} 首)',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Live Transport Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _state.currentTrack?.title ?? '尚未开始播放',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${_state.currentIndex >= 0 ? _state.currentIndex + 1 : 0}/${_state.queueCount}',
                        style: const TextStyle(fontSize: 12, color: FideluneColors.textSecondary),
                      ),
                    ],
                  ),
                  Slider(
                    value: _state.durationSeconds > 0
                        ? _state.positionSeconds.clamp(0, _state.durationSeconds)
                        : 0,
                    max: _state.durationSeconds > 0 ? _state.durationSeconds : 1,
                    onChanged: _state.durationSeconds > 0
                        ? (v) => widget.gateway.seek(v)
                        : null,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatSeconds(_state.positionSeconds),
                          style: const TextStyle(fontSize: 11.5, color: FideluneColors.textSecondary)),
                      Text(formatSeconds(_state.durationSeconds),
                          style: const TextStyle(fontSize: 11.5, color: FideluneColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.outlined(
                        tooltip: '上一首',
                        onPressed: () => widget.gateway.previous(),
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      FilledButton.icon(
                        onPressed: () => widget.gateway.togglePlayPause(),
                        icon: Icon(_state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        label: Text(_state.isPlaying ? '暂停' : '继续'),
                      ),
                      IconButton.outlined(
                        tooltip: '下一首',
                        onPressed: () => widget.gateway.next(),
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                      IconButton.outlined(
                        tooltip: '停止',
                        color: FideluneColors.coral,
                        onPressed: () => widget.gateway.stop(),
                        icon: const Icon(Icons.stop_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          SignalPathCard(snapshot: _state.signalPath),
          const SizedBox(height: 12),

          // Per-rate DAC screen readout recorder (e.g. D1)
          if (_item.dacRateChecklistHz.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DX5 II 屏幕实测核对（请根据 DAC 面板实际显示点选）',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    for (final hz in _item.dacRateChecklistHz)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 78,
                              child: Text(formatHz(hz),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ),
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                children: ['匹配', '降频48k', '无声/不支持'].map((opt) {
                                  final selected = _dacRateObservations[hz] == opt;
                                  return ChoiceChip(
                                    label: Text(opt, style: const TextStyle(fontSize: 11.5)),
                                    selected: selected,
                                    onSelected: (_) {
                                      setState(() => _dacRateObservations[hz] = opt);
                                      widget.controller.updateDraftObservation(
                                        itemId: _item.id,
                                        dacRateObservations: _dacRateObservations,
                                      );
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Pass Criteria & Notes
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('通过标准', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final crit in _item.passCriteria)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline, size: 16, color: FideluneColors.emerald),
                          const SizedBox(width: 6),
                          Expanded(child: Text(crit, style: const TextStyle(fontSize: 12.5))),
                        ],
                      ),
                    ),
                  if (_item.failureTags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('异常快选标签（如有问题可勾选）',
                        style: TextStyle(fontSize: 12.5, color: FideluneColors.textSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _item.failureTags.map((tag) {
                        final selected = _selectedTags.contains(tag);
                        return FilterChip(
                          label: Text(tag, style: const TextStyle(fontSize: 12)),
                          selected: selected,
                          selectedColor: FideluneColors.coral.withValues(alpha: 0.25),
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                _selectedTags.add(tag);
                              } else {
                                _selectedTags.remove(tag);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '人工观察备注（如 DAC 显示、听感或异常现象）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Verdict Buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: FideluneColors.emerald),
                  onPressed: () => _saveOutcome(TestItemStatus.passed, moveNext: true),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('通过并下一项'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: FideluneColors.coral),
                  onPressed: () => _saveOutcome(TestItemStatus.failed, moveNext: false),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('标记未通过'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _launchTestAudio,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试本项'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _saveOutcome(TestItemStatus.skipped, moveNext: true),
                  icon: const Icon(Icons.skip_next_rounded, size: 18),
                  label: const Text('暂跳过并继续'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
