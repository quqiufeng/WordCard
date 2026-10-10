import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'pages/study_page.dart';
import 'theme/app_theme.dart';

class WordCardApp extends StatelessWidget {
  const WordCardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      builder: (context, yaru, child) => MaterialApp(
        title: 'WordCard',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.apply(yaru.theme), // 自动匹配系统浅色主题
        darkTheme: AppTheme.apply(yaru.darkTheme), // 自动匹配系统深色主题
        themeMode: ThemeMode.system, // 跟随系统切换
        // 全局窗口标题栏（含 Ubuntu 窗口控制按钮），置于路由之外。
        builder: (context, child) => Scaffold(
          appBar: YaruWindowTitleBar(
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Image.asset(
                'assets/icons/wordcard.png',
                width: 18,
                height: 18,
              ),
            ),
            title: const Text('WordCard · 读前预习词汇'),
          ),
          body: child ?? const SizedBox.shrink(),
        ),
        home: const StudyPage(),
      ),
    );
  }
}
