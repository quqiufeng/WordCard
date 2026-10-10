import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 隐藏原生标题栏并启用 YaruWindow 窗口控制。
  await YaruWindowTitleBar.ensureInitialized();
  runApp(const WordCardApp());
}
