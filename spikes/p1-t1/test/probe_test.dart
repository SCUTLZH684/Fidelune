import 'package:fidelune_p1t1/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the installed build and reads stored fixture markers', (
    tester,
  ) async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('fidelune/p1t1');
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {
        'build': '2',
        'media': call.method == 'seed' ? '9bf439a61fab' : '未写入',
        'organization': '1A863DCE',
        'bookmark': 'cbe601a4db8a · 标记可读',
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const ProbeApp());
    await tester.pumpAndSettle();
    expect(find.text('构建 2'), findsOneWidget);

    await tester.tap(find.text('写入测试数据'));
    await tester.pumpAndSettle();
    expect(calls, ['inspect', 'seed']);
    expect(find.text('媒体文件 9bf439a61fab'), findsOneWidget);
    expect(find.text('组织记录 1A863DCE'), findsOneWidget);
    expect(find.text('目录书签 cbe601a4db8a · 标记可读'), findsOneWidget);
  });
}
