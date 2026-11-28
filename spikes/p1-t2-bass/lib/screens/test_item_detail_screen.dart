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
  double? _dragSeconds;

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
    _dragSeconds = null;
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _alertSub?.cancel();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _launchSubAction(TestSubAction action) async {
    if (action.requiresVolumeBelowFull &&
        _state.dacProfile.isUsbDac &&
        _state.dacProfile.outputVolume >= 0.999) {
      setState(() {
        _latestAlert = '请先按一下 iPhone 侧边音量减键（将音量降至 100% 以下），再点击「${action.label}」验证安全拦截，避免直接起播。';
      });
      return;
    }

    if (action.requiresDopSafety && !_state.dopSafetyAcknowledged) {
      final confirmed = await DopSafetyDialog.showAndConfirm(context, _state.dacProfile);
      if (!confirmed) return;
      await widget.gateway.acknowledgeDopSafety(true);
    }

    final tracks = action.fixtureFiles
        .map((name) => widget.tracksByName[name])
        .whereType<TrackSpec>()
        .toList();
    if (tracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到本步骤所需的内置测试音源')),
        );
      }
      return;
    }

    setState(() => _latestAlert = null);
    await widget.gateway.setPlaybackMode(action.playbackMode);
    await widget.gateway.setDsdMode(action.dsdMode);
    await widget.gateway.playQueue(tracks, dsdMode: action.dsdMode);
  }

  Future<void> _saveOutcome(TestItemStatus status, {bool moveNext = false}) async {
    final effectiveStatus = status;
    await widget.controller.markResult(
      itemId: _item.id,
      status: effectiveStatus,
      notes: _notesController.text.trim(),
      selectedTags: _selectedTags.toList(),
      dacRateObservations: _dacRateObservations,
      routeName: '${_state.dacProfile.deviceName} (${_state.dacProfile.routeKind})',
    );
    if (!mounted) return;
    final storedStatus = widget.controller.recordFor(_item.id).status;
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
        const SnackBar(content: Text('当前全部复测项已处理完毕，可前往「报告导出」分享！')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_item.id} 已记录为：${storedStatus.label}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final rec = widget.controller.recordFor(_item.id);
        final dac = _state.dacProfile;
        final missingUsbWarning = _item.requiresUsbDac && !dac.isUsbDac;
        final blockReason = widget.controller.passBlockReason(
          item: _item,
          selectedTags: _selectedTags.toList(),
          dacRateObservations: _dacRateObservations,
        );

        final dur = _state.durationSeconds;
        final sliderVal = dur > 0 ? (_dragSeconds ?? _state.positionSeconds).clamp(0.0, dur) : 0.0;
        final sweepByHz = <int, DacProbeResult>{
          for (final res in widget.controller.usbSweepResults) res.requestedHz: res,
        };

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

              if (_item.requiresHeadphonesUnplugged)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: FideluneColors.coral.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: FideluneColors.coral.withValues(alpha: 0.75)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.headset_off_rounded, color: FideluneColors.coral),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '高风险安全提示：开始本项 DoP 测试前，必须先从 DX5 II / 耳放物理拔下耳机！先仅观察 DAC 屏幕确认点亮 DSD，确认锁灯无误后再把耳放调至最低音量插上耳机试听。',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: FideluneColors.coral),
                        ),
                      ),
                    ],
                  ),
                ),

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

              // Clear "What to tap / What to observe / How to judge" card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('操作与判断引导', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _item.steps.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${i + 1}. ${_item.steps[i]}',
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ),
                      const Divider(height: 16),
                      _GuideRow(title: '观察什么', body: _item.observeGuide, color: FideluneColors.sky),
                      const SizedBox(height: 6),
                      _GuideRow(title: '怎么判断', body: _item.judgeGuide, color: FideluneColors.emerald),
                      const SizedBox(height: 12),
                      if (_item.supportsRateSweep) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: widget.controller.runningUsbSweep
                                ? null
                                : () => widget.controller.runUsbRateSweep(),
                            icon: widget.controller.runningUsbSweep
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.radar_rounded, size: 18),
                            label: Text(
                              widget.controller.runningUsbSweep
                                  ? '正在探测 8 档采样率握手...'
                                  : '一键自动探测 8 档采样率握手（机器核对 44.1→384 kHz）',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      for (final action in _item.subActions) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _launchSubAction(action),
                            icon: Icon(
                              action.requiresDopSafety ? Icons.security_rounded : Icons.play_circle_fill_rounded,
                              size: 19,
                            ),
                            label: Text(action.label),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 3, bottom: 9, left: 4),
                          child: Text(
                            action.description,
                            style: const TextStyle(fontSize: 11.5, color: FideluneColors.textSecondary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Live Transport Card (Seek commits cleanly in onChangeEnd)
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
                              _state.currentTrack?.title ?? '点击上方动作按钮开始播放',
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
                        value: sliderVal,
                        max: dur > 0 ? dur : 1.0,
                        onChanged: dur > 0 ? (v) => setState(() => _dragSeconds = v) : null,
                        onChangeEnd: dur > 0
                            ? (v) async {
                                setState(() => _dragSeconds = null);
                                await widget.gateway.seek(v);
                              }
                            : null,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(formatSeconds(_dragSeconds ?? _state.positionSeconds),
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

              // Per-rate DAC screen readout recorder (e.g. T2 including 352.8 kHz)
              if (_item.dacRateChecklistHz.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DX5 II 前面板读数核对（须全部 8 档点选「匹配」方可通过）',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '上方「机器握手」仅代表 iOS/BASS 层读数；下方选项请以 DX5 II 实体屏幕为准。',
                          style: TextStyle(fontSize: 11.5, color: FideluneColors.textSecondary),
                        ),
                        const SizedBox(height: 10),
                        for (final hz in _item.dacRateChecklistHz) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(formatHz(hz),
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                    if (hz == 352800) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: FideluneColors.sky.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('DSD128 母频必核',
                                            style: TextStyle(fontSize: 10.5, color: FideluneColors.sky)),
                                      ),
                                    ],
                                    const Spacer(),
                                    if (sweepByHz[hz] != null)
                                      Text(
                                        sweepByHz[hz]!.matchedTarget
                                            ? '机器已锁 (${sweepByHz[hz]!.settleElapsedMs}ms)'
                                            : '机器未锁(${formatHz(sweepByHz[hz]!.sessionActualHz)})',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: sweepByHz[hz]!.matchedTarget
                                              ? FideluneColors.emerald
                                              : FideluneColors.coral,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Wrap(
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
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Pass Criteria, Failure Tags & Notes
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
                        const Text('阻塞异常标签（勾选后将锁定禁止标为「通过」）',
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
                                widget.controller.updateDraftObservation(
                                  itemId: _item.id,
                                  selectedTags: _selectedTags.toList(),
                                );
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
              const SizedBox(height: 12),

              if (blockReason != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: FideluneColors.amber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: FideluneColors.amber.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 18, color: FideluneColors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          blockReason,
                          style: const TextStyle(fontSize: 12, color: FideluneColors.amber, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

              // Verdict Buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: FideluneColors.emerald),
                      onPressed: blockReason != null
                          ? null
                          : () => _saveOutcome(TestItemStatus.passed, moveNext: true),
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
                      onPressed: _item.subActions.isEmpty
                          ? null
                          : () => _launchSubAction(_item.subActions.first),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('重跑本项首个动作'),
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
      },
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.title, required this.body, required this.color});
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$title：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          Expanded(child: Text(body, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
