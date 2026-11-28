import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../audio/audio_engine_gateway.dart';
import '../models/audio_models.dart';
import 'acceptance_catalog.dart';

enum TestItemStatus {
  pending('待测试'),
  passed('已通过'),
  failed('未通过'),
  skipped('暂跳过');

  const TestItemStatus(this.label);
  final String label;

  static TestItemStatus fromWire(String? raw) {
    return TestItemStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => TestItemStatus.pending,
    );
  }
}

class AcceptanceRecord {
  const AcceptanceRecord({
    required this.itemId,
    this.status = TestItemStatus.pending,
    this.attempts = 0,
    this.updatedAtIso,
    this.notes = '',
    this.selectedTags = const [],
    this.dacRateObservations = const {},
    this.lastRouteObserved = '',
  });

  final String itemId;
  final TestItemStatus status;
  final int attempts;
  final String? updatedAtIso;
  final String notes;
  final List<String> selectedTags;
  final Map<int, String> dacRateObservations;
  final String lastRouteObserved;

  AcceptanceRecord copyWith({
    TestItemStatus? status,
    int? attempts,
    String? updatedAtIso,
    String? notes,
    List<String>? selectedTags,
    Map<int, String>? dacRateObservations,
    String? lastRouteObserved,
  }) {
    return AcceptanceRecord(
      itemId: itemId,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
      notes: notes ?? this.notes,
      selectedTags: selectedTags ?? this.selectedTags,
      dacRateObservations: dacRateObservations ?? this.dacRateObservations,
      lastRouteObserved: lastRouteObserved ?? this.lastRouteObserved,
    );
  }

  Map<String, dynamic> toMap() => {
        'itemId': itemId,
        'status': status.name,
        'attempts': attempts,
        'updatedAtIso': updatedAtIso,
        'notes': notes,
        'selectedTags': selectedTags,
        'dacRateObservations': dacRateObservations.map((k, v) => MapEntry('$k', v)),
        'lastRouteObserved': lastRouteObserved,
      };

  factory AcceptanceRecord.fromMap(Map<String, dynamic> map) {
    final obsRaw = (map['dacRateObservations'] as Map?) ?? const {};
    final obs = <int, String>{};
    for (final entry in obsRaw.entries) {
      final k = int.tryParse(entry.key.toString());
      if (k != null) {
        obs[k] = entry.value.toString();
      }
    }
    return AcceptanceRecord(
      itemId: map['itemId'] as String? ?? '',
      status: TestItemStatus.fromWire(map['status'] as String?),
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      updatedAtIso: map['updatedAtIso'] as String?,
      notes: map['notes'] as String? ?? '',
      selectedTags: ((map['selectedTags'] as List?) ?? const []).map((e) => e.toString()).toList(),
      dacRateObservations: obs,
      lastRouteObserved: map['lastRouteObserved'] as String? ?? '',
    );
  }
}

class AcceptanceController extends ChangeNotifier {
  AcceptanceController(this._gateway);

  final AudioEngineGateway _gateway;

  final Map<String, AcceptanceRecord> _records = {
    for (final item in acceptanceCatalog) item.id: AcceptanceRecord(itemId: item.id),
  };
  List<SelfTestResult> _autoResults = const [];
  bool _runningAutoTests = false;
  String? _lastAutoRunIso;

  List<DacProbeResult> _usbSweepResults = const [];
  bool _runningUsbSweep = false;

  List<SelfTestResult> get autoResults => _autoResults;
  bool get runningAutoTests => _runningAutoTests;
  String? get lastAutoRunIso => _lastAutoRunIso;
  List<DacProbeResult> get usbSweepResults => _usbSweepResults;
  bool get runningUsbSweep => _runningUsbSweep;

  AcceptanceRecord recordFor(String itemId) =>
      _records[itemId] ?? AcceptanceRecord(itemId: itemId);

  int get totalManualCount => acceptanceCatalog.length;
  int get passedManualCount =>
      _records.values.where((r) => r.status == TestItemStatus.passed).length;
  int get failedManualCount =>
      _records.values.where((r) => r.status == TestItemStatus.failed).length;
  int get completedManualCount =>
      _records.values.where((r) => r.status != TestItemStatus.pending).length;

  int get passedAutoCount => _autoResults.where((r) => r.passed).length;
  int get totalAutoCount => _autoResults.length;

  Future<void> loadPersistedState() async {
    try {
      final raw = await _gateway.loadAcceptanceState();
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final recs = (decoded['records'] as List?) ?? const [];
      for (final entry in recs.whereType<Map>()) {
        final r = AcceptanceRecord.fromMap(entry.cast<String, dynamic>());
        if (_records.containsKey(r.itemId)) {
          _records[r.itemId] = r;
        }
      }
      final autos = (decoded['autoResults'] as List?) ?? const [];
      _autoResults = autos
          .whereType<Map>()
          .map((e) => SelfTestResult.fromMap(e.cast<String, dynamic>()))
          .toList();
      _lastAutoRunIso = decoded['lastAutoRunIso'] as String?;
      notifyListeners();
    } catch (_) {
      // Corrupt persisted state falls back to clean default records.
    }
  }

  Future<void> runAutomatedChecks() async {
    if (_runningAutoTests) return;
    _runningAutoTests = true;
    notifyListeners();
    try {
      _autoResults = await _gateway.runAutomatedSelfTests();
      _lastAutoRunIso = DateTime.now().toIso8601String();
      await _persist();
    } finally {
      _runningAutoTests = false;
      notifyListeners();
    }
  }

  Future<void> runUsbRateSweep() async {
    if (_runningUsbSweep) return;
    _runningUsbSweep = true;
    notifyListeners();
    try {
      _usbSweepResults = await _gateway.runUsbDacRateSweep();
    } finally {
      _runningUsbSweep = false;
      notifyListeners();
    }
  }

  /// Returns a non-null Chinese explanation when marking [item] as passed must be blocked
  /// (e.g. any failure tag selected, or any required DAC rate observation missing/non-matching).
  String? passBlockReason({
    required AcceptanceTestItem item,
    required List<String> selectedTags,
    required Map<int, String> dacRateObservations,
  }) {
    if (selectedTags.isNotEmpty) {
      return '已勾选异常标签（${selectedTags.join('、')}），不允许标为「通过」。请点「标记未通过」或先取消误选标签。';
    }
    if (item.dacRateChecklistHz.isNotEmpty) {
      final missingRates = <String>[];
      final mismatchedRates = <String>[];
      for (final hz in item.dacRateChecklistHz) {
        final obs = dacRateObservations[hz];
        if (obs == null || obs.isEmpty) {
          missingRates.add(formatHz(hz));
        } else if (obs != '匹配') {
          mismatchedRates.add('${formatHz(hz)}($obs)');
        }
      }
      if (mismatchedRates.isNotEmpty) {
        return '存在未匹配频点（${mismatchedRates.join('、')}），不允许标为「通过」，请点「标记未通过」。';
      }
      if (missingRates.isNotEmpty) {
        return '请先点选核对所有 ${item.dacRateChecklistHz.length} 档 DAC 屏幕读数（尚缺：${missingRates.join('、')}），全部「匹配」后方可标为通过。';
      }
    }
    return null;
  }

  Future<void> markResult({
    required String itemId,
    required TestItemStatus status,
    String? notes,
    List<String>? selectedTags,
    Map<int, String>? dacRateObservations,
    String? routeName,
  }) async {
    final prev = recordFor(itemId);
    final effectiveTags = selectedTags ?? prev.selectedTags;
    final effectiveObs = dacRateObservations ?? prev.dacRateObservations;
    final item = acceptanceCatalog.cast<AcceptanceTestItem?>().firstWhere(
          (e) => e?.id == itemId,
          orElse: () => null,
        );

    var effectiveStatus = status;
    if (status == TestItemStatus.passed) {
      if (effectiveTags.isNotEmpty) {
        // Hard guardrail: blocking failure tags cannot produce a passed verdict.
        effectiveStatus = TestItemStatus.failed;
      } else if (item != null &&
          passBlockReason(item: item, selectedTags: effectiveTags, dacRateObservations: effectiveObs) != null &&
          effectiveTags.isEmpty) {
        // Only coerce to failed if non-matching observations exist
        final hasMismatch = item.dacRateChecklistHz.any(
          (hz) => effectiveObs[hz] != null && effectiveObs[hz]!.isNotEmpty && effectiveObs[hz] != '匹配',
        );
        if (hasMismatch) {
          effectiveStatus = TestItemStatus.failed;
        }
      }
    }

    final updated = prev.copyWith(
      status: effectiveStatus,
      attempts: effectiveStatus == TestItemStatus.pending ? prev.attempts : prev.attempts + 1,
      updatedAtIso: DateTime.now().toIso8601String(),
      notes: notes ?? prev.notes,
      selectedTags: effectiveTags,
      dacRateObservations: effectiveObs,
      lastRouteObserved: routeName ?? prev.lastRouteObserved,
    );
    _records[itemId] = updated;
    notifyListeners();
    await _persist();
  }

  Future<void> updateDraftObservation({
    required String itemId,
    String? notes,
    List<String>? selectedTags,
    Map<int, String>? dacRateObservations,
  }) async {
    final prev = recordFor(itemId);
    _records[itemId] = prev.copyWith(
      notes: notes ?? prev.notes,
      selectedTags: selectedTags ?? prev.selectedTags,
      dacRateObservations: dacRateObservations ?? prev.dacRateObservations,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> resetAll() async {
    for (final item in acceptanceCatalog) {
      _records[item.id] = AcceptanceRecord(itemId: item.id);
    }
    _autoResults = const [];
    _lastAutoRunIso = null;
    notifyListeners();
    await _persist();
  }

  /// Checkpoint resume: returns the first failed item if retrying, otherwise first pending item.
  AcceptanceTestItem? nextPendingItem({String? afterId}) {
    if (afterId != null) {
      final idx = acceptanceCatalog.indexWhere((e) => e.id == afterId);
      if (idx >= 0) {
        for (var i = idx + 1; i < acceptanceCatalog.length; i++) {
          final item = acceptanceCatalog[i];
          if (recordFor(item.id).status == TestItemStatus.pending) {
            return item;
          }
        }
      }
    }
    for (final item in acceptanceCatalog) {
      if (recordFor(item.id).status == TestItemStatus.pending) {
        return item;
      }
    }
    for (final item in acceptanceCatalog) {
      if (recordFor(item.id).status == TestItemStatus.failed) {
        return item;
      }
    }
    return null;
  }

  String toJsonReport(PlaybackStateSnapshot state) {
    final payload = {
      'generatedAt': DateTime.now().toIso8601String(),
      'lastAutoRunIso': _lastAutoRunIso,
      'dacProfile': {
        'deviceName': state.dacProfile.deviceName,
        'routeKind': state.dacProfile.routeKind,
        'sessionRateHz': state.dacProfile.currentSessionSampleRateHz,
        'bassDeviceRateHz': state.dacProfile.bassDeviceSampleRateHz,
        'probedSupportedRatesHz': state.dacProfile.probedSupportedRatesHz,
      },
      'settings': state.settings.toMap(),
      'autoResults': _autoResults.map((e) => e.toMap()).toList(),
      'manualRecords': _records.values.map((e) => e.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  String toMarkdownReport(PlaybackStateSnapshot state) {
    final buf = StringBuffer();
    buf.writeln('# Fidelune BASS 真机集中验收报告');
    buf.writeln();
    buf.writeln('- 生成时间: `${DateTime.now().toIso8601String()}`');
    buf.writeln('- 当前路由: `${state.dacProfile.deviceName}` (`${state.dacProfile.routeKind}`)');
    buf.writeln('- 机器自动校验: `$passedAutoCount / $totalAutoCount`');
    buf.writeln('- 人工真机验收: 通过 `$passedManualCount` / 失败 `$failedManualCount` / 总计 `$totalManualCount`');
    buf.writeln();
    buf.writeln('## 1. 机器自动化基线校验');
    if (_autoResults.isEmpty) {
      buf.writeln('_尚未在真机运行自动校验。_');
    } else {
      buf.writeln('| ID | 检查项 | 结果 | 耗时(ms) | 摘要 |');
      buf.writeln('| --- | --- | --- | ---: | --- |');
      for (final r in _autoResults) {
        buf.writeln('| `${r.id}` | ${r.title} | ${r.passed ? '通过' : '失败'} | ${r.durationMs} | ${r.summary} |');
      }
    }
    buf.writeln();
    buf.writeln('## 2. 真机人工与外设验收明细');
    buf.writeln('| ID | 分类 | 项目 | 状态 | 次数 | 观测路由 | 问题标签 / 备注 |');
    buf.writeln('| --- | --- | --- | --- | ---: | --- | --- |');
    for (final item in acceptanceCatalog) {
      final rec = recordFor(item.id);
      final tagPart = rec.selectedTags.isEmpty ? '' : '[${rec.selectedTags.join(', ')}] ';
      final dacObs = rec.dacRateObservations.isEmpty
          ? ''
          : ' DAC读数: ${rec.dacRateObservations.entries.map((e) => '${formatHz(e.key)}=${e.value}').join('; ')}';
      final noteText = '$tagPart${rec.notes}$dacObs'.replaceAll('\n', ' ').trim();
      buf.writeln(
        '| `${item.id}` | ${item.group.title} | ${item.title} | **${rec.status.label}** | ${rec.attempts} | ${rec.lastRouteObserved.isEmpty ? '-' : rec.lastRouteObserved} | ${noteText.isEmpty ? '-' : noteText} |',
      );
    }
    return buf.toString();
  }

  Future<void> _persist() async {
    final jsonStr = jsonEncode({
      'lastAutoRunIso': _lastAutoRunIso,
      'autoResults': _autoResults.map((e) => e.toMap()).toList(),
      'records': _records.values.map((e) => e.toMap()).toList(),
    });
    await _gateway.saveAcceptanceState(jsonStr);
  }
}
