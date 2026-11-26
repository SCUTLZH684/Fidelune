import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const ProbeApp());

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ProbePage(),
    );
  }
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  static const platform = MethodChannel('fidelune/p1t1');
  Map<String, String> snapshot = {};
  String? message;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    run('inspect');
  }

  Future<void> run(String method) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result = await platform.invokeMapMethod<String, String>(method);
      if (mounted && result != null) {
        setState(() {
          snapshot = result;
          if (method == 'log') message = '已发送 FIDELUNE_P1T1 日志';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => message = '操作失败（${error.code}）');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmCrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('触发一次诊断崩溃？'),
        content: const Text('应用会关闭。重新打开可继续检查测试数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('触发崩溃'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await run('crash');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fidelune P1-T1')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('构建 ${snapshot['build'] ?? '…'}'),
          Text('媒体文件 ${snapshot['media'] ?? '…'}'),
          Text('组织记录 ${snapshot['organization'] ?? '…'}'),
          Text('目录书签 ${snapshot['bookmark'] ?? '…'}'),
          if (message != null) Text(message!),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : () => run('seed'),
            child: const Text('写入测试数据'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => run('chooseFolder'),
            child: const Text('选择外部测试目录'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => run('inspect'),
            child: const Text('读取测试数据'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => run('log'),
            child: const Text('发送诊断日志'),
          ),
          OutlinedButton(
            onPressed: busy ? null : confirmCrash,
            child: const Text('验证崩溃回收'),
          ),
        ],
      ),
    );
  }
}
