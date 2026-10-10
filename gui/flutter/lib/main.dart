import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'app.dart';
import 'automation/automation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 隐藏原生标题栏并启用 YaruWindow 窗口控制。
  await YaruWindowTitleBar.ensureInitialized();
  // 启动 UI 自动化桥（Unix socket，供 AI agent 驱动）。
  try {
    await Automation.instance.start();
  } catch (e) {
    debugPrint('automation bridge failed: $e');
  }
  runApp(const WordCardApp());
}
