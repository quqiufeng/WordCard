import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'pages/study_page.dart';
import 'theme/app_theme.dart';

/// 全局导航 key（供托盘「显示窗口」用）。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class WordCardApp extends StatelessWidget {
  const WordCardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      builder: (context, yaru, child) => MaterialApp(
        title: 'WordCard',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        theme: AppTheme.apply(yaru.theme),
        darkTheme: AppTheme.apply(yaru.darkTheme),
        themeMode: ThemeMode.system,
        // 全局窗口标题栏（含 Ubuntu 窗口控制按钮），置于路由之外。
        builder: (context, child) => Scaffold(
          backgroundColor: Kami.parchment,
          appBar: const YaruWindowTitleBar(
            // 关闭 → 最小化到任务栏/托盘（不销毁窗口，避免崩溃/自动重启）
            onClose: YaruWindow.minimize,
            title: Text('WordCard · 读前预习词汇'),
          ),
          body: child ?? const SizedBox.shrink(),
        ),
        home: const StudyPage(),
      ),
    );
  }
}
