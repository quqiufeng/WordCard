import 'package:flutter/material.dart';

import '../automation/automation.dart';
import '../ffi/wordcard.dart';
import '../state/study_session.dart';
import '../theme/app_theme.dart';
import '../tts.dart';
import 'dashboard_page.dart';
import 'import_page.dart';
import 'review_screen.dart';
import 'tasks_page.dart';

/// 主页面：初始化引擎，承载可折叠侧栏（首页 / 任务 / 导入）。
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  static const _titles = ['首页', '任务', '导入'];
  static const _navIds = ['home', 'tasks', 'import'];
  static const _icons = [
    Icons.home_outlined,
    Icons.list_alt_outlined,
    Icons.menu_book_outlined,
  ];

  WordCardEngine? _engine;
  int? _userId;
  String? _error;
  int _index = 0;
  bool _showNav = true;

  @override
  void initState() {
    super.initState();
    final a = Automation.instance;
    a.register('nav.toggle', () => setState(() => _showNav = !_showNav));
    for (var i = 0; i < _navIds.length; i++) {
      final idx = i;
      a.register('nav.${_navIds[i]}', () => setState(() => _index = idx));
    }
    _init();
  }

  Future<void> _init() async {
    try {
      final engine = WordCardEngine.open();
      final userId = engine.findOrCreateUser();
      if (!mounted) return;
      setState(() {
        _engine = engine;
        _userId = userId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// 打开记忆（复习）页：ids 为空表示今日队列。
  void _pushReview(List<int>? ids, String title) {
    final engine = _engine;
    final uid = _userId;
    if (engine == null || uid == null) return;
    final session = StudySession(engine: engine, userId: uid);
    if (ids == null) {
      session.start();
    } else {
      session.startItems(ids);
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReviewScreen(session: session, title: title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _errorView(context);
    if (_engine == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: _showNav ? 200 : 0,
          child: _showNav ? _nav(context) : const SizedBox.shrink(),
        ),
        if (_showNav) const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              _header(context),
              Expanded(child: _content()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nav(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListView(
        primary: false,
        children: [
          for (var i = 0; i < _titles.length; i++)
            ListTile(
              selected: i == _index,
              selectedTileColor: ChinaColors.shuangdi,
              leading: Icon(_icons[i]),
              title: Text(_titles[i]),
              onTap: () => Automation.instance.invoke('nav.${_navIds[i]}'),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            tooltip: _showNav ? '隐藏侧栏' : '显示侧栏',
            icon: Icon(_showNav ? Icons.menu_open : Icons.menu),
            onPressed: () => Automation.instance.invoke('nav.toggle'),
          ),
          Text(_titles[_index], style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _content() => switch (_index) {
        0 => DashboardPage(
            engine: _engine!,
            userId: _userId!,
            onStartReview: () => _pushReview(null, '今日记忆'),
            onOpenTask: (_) => setState(() => _index = 1),
          ),
        1 => TasksPage(
            engine: _engine!,
            userId: _userId!,
            onSpeak: (t) => TtsService.instance.speak(t),
            onStudy: (ids, name) => _pushReview(ids, '记忆 · $name'),
          ),
        _ => ImportPage(engine: _engine!),
      };

  Widget _errorView(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('引擎加载失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              '$_error\n\n请先编译 C 核心库：cd src && make',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
