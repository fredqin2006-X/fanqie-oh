import 'package:flutter/material.dart';

import 'platform/harmony_bootstrap.dart';

void main() => runApp(const FqApp());

class FqApp extends StatelessWidget {
  const FqApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'fqapp 鸿蒙版',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffb74732)),
      scaffoldBackgroundColor: const Color(0xfffaf7f2),
      useMaterial3: true,
    ),
    home: const BootstrapPage(),
  );
}

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  late Future<BootstrapReport> _report;

  @override
  void initState() {
    super.initState();
    _report = HarmonyBootstrap.inspect();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('fqapp 鸿蒙版')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(
                Icons.menu_book_rounded,
                size: 64,
                color: Color(0xffb74732),
              ),
              const SizedBox(height: 20),
              Text(
                '从阅读开始，向鸿蒙迈进',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text('内部移植验证版 · G1\n当前验证启动与本地数据基础，阅读、搜索和播放尚未接入。'),
              const SizedBox(height: 24),
              FutureBuilder<BootstrapReport>(
                future: _report,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('本地数据初始化失败，尚未进入书库。'),
                            const SizedBox(height: 8),
                            Text(
                              HarmonyBootstrap.describeError(snapshot.error),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => setState(() {
                                _report = HarmonyBootstrap.inspect();
                              }),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final report = snapshot.data;
                  if (report == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Card(
                    child: Column(
                      children: [
                        _check('原生界面已启动', 'Flutter-OH · Dart 3.12.2'),
                        _check(
                          '系统版本',
                          'API ${report.apiVersion} · 最低要求 API 23',
                        ),
                        _check(
                          '应用私有目录',
                          report.fileReused ? '冷启动后文件保留' : '首次写入并回读成功',
                        ),
                        _check('偏好设置', '持久启动计数：${report.launchCount}'),
                        _check(
                          '安全密钥',
                          report.keyReused
                              ? 'HUKS 解封成功，沿用既有密钥'
                              : 'HUKS 加密保存并回读成功',
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Text(
                '模拟器结果与 6.1 真机验收分别记录。书库和媒体能力会在桥接验证通过后逐项接入。',
                style: TextStyle(color: Color(0xff6f6862)),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _check(String title, String subtitle) => ListTile(
    leading: const Icon(Icons.check_circle_outline, color: Color(0xff447457)),
    title: Text(title),
    subtitle: Text(subtitle),
  );
}
