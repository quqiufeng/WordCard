import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaru/yaru.dart';

import '../ffi/wordcard.dart';
import '../state/study_session.dart';
import '../theme/app_theme.dart';
import '../widgets/flash_card.dart';
import '../widgets/review_queue.dart';
import '../widgets/stats_widget.dart';
import 'import_page.dart';

/// 主页面：初始化引擎与会话，承载 Yaru 主从布局。
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  static const _titles = ['复习', '队列', '统计', '导入'];
  static const _icons = [
    Icons.school_outlined,
    Icons.list_alt_outlined,
    Icons.insights_outlined,
    Icons.menu_book_outlined,
  ];

  WordCardEngine? _engine;
  StudySession? _session;
  String? _error;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final engine = WordCardEngine.open();
      final userId = engine.findOrCreateUser();
      final session = StudySession(engine: engine, userId: userId);
      session.start();
      if (!mounted) return;
      setState(() {
        _engine = engine;
        _session = session;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _errorView(context);
    final session = _session;
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return YaruMasterDetailPage(
      length: _titles.length,
      initialIndex: _index,
      onSelected: (i) {
        if (i != null) _index = i;
      },
      tileBuilder: (context, index, selected, width) => YaruMasterTile(
        leading: Icon(_icons[index]),
        title: Text(_titles[index]),
      ),
      pageBuilder: (context, index) => switch (index) {
        0 => _ReviewPage(session: session),
        1 => _QueuePage(session: session),
        2 => _StatsPage(session: session, engine: _engine!),
        _ => ImportPage(engine: _engine!),
      },
    );
  }

  Widget _errorView(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: theme.colorScheme.error),
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

// ────────────────────────────── 复习 ──────────────────────────────

class _ReviewPage extends StatefulWidget {
  const _ReviewPage({required this.session});

  final StudySession session;

  @override
  State<_ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<_ReviewPage> {
  StudySession get s => widget.session;

  void _know() {
    if (s.finished) {
      s.start();
      return;
    }
    s.grade(4);
  }

  void _dontKnow() {
    if (s.finished) {
      s.start();
      return;
    }
    s.grade(1);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => CallbackShortcuts(
        bindings: {
          // 空格 = 不会；方向右键 = 记得并下一张
          const SingleActivator(LogicalKeyboardKey.space): _dontKnow,
          const SingleActivator(LogicalKeyboardKey.arrowRight): _know,
        },
        child: Focus(
          autofocus: true,
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (s.finished) return _finished(context);
    final card = s.current;
    if (card == null) return _empty(context);

    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Expanded(
              child: FlashCard(
                card: card,
                flipped: s.flipped,
                onFlip: s.flip,
              ),
            ),
            const SizedBox(height: 16),
            _controls(context),
          ],
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('点击卡片看释义，然后自评', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: ChinaColors.orange),
                onPressed: _dontKnow,
                icon: const Icon(Icons.close),
                label: const Text('不会（空格）'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: ChinaColors.qinglv),
                onPressed: _know,
                icon: const Icon(Icons.check),
                label: const Text('记得（→）'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _finished(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 56, color: ChinaColors.qinglv),
          const SizedBox(height: 16),
          Text('今日复习完成！', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('共 ${s.total} 张', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => s.start(),
            icon: const Icon(Icons.refresh),
            label: const Text('再来一轮'),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 48, color: ChinaColors.dim),
          const SizedBox(height: 16),
          Text('今日没有需要复习的内容', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('可在「导入」中添加电子书词汇', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ────────────────────────────── 队列 / 统计 ──────────────────────────────

class _QueuePage extends StatelessWidget {
  const _QueuePage({required this.session});

  final StudySession session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: ReviewQueue(session: session),
      ),
    );
  }
}

class _StatsPage extends StatelessWidget {
  const _StatsPage({required this.session, required this.engine});

  final StudySession session;
  final WordCardEngine engine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('学习统计', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            StatsWidget(session: session),
            const SizedBox(height: 32),
            Text('引擎', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('libwordcard.so · v${engine.version}',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
