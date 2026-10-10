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
        _ => const ImportPage(),
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

  void _space() {
    if (s.finished) {
      s.start();
    } else if (s.awaitingNext) {
      s.next();
    } else {
      s.flip();
    }
  }

  void _score(int quality) {
    if (s.current != null && !s.awaitingNext) s.submit(quality);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _space,
          const SingleActivator(LogicalKeyboardKey.digit1): () => _score(1),
          const SingleActivator(LogicalKeyboardKey.digit2): () => _score(3),
          const SingleActivator(LogicalKeyboardKey.digit3): () => _score(4),
          const SingleActivator(LogicalKeyboardKey.digit4): () => _score(5),
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
    if (s.awaitingNext) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatsWidget(session: s),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: s.next,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('下一张（空格）'),
            ),
          ),
        ],
      );
    }

    if (!s.flipped) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: s.flip,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('显示答案（空格）'),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('这张卡片记得如何？', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _scoreButton(1, '忘记', ChinaColors.zhusha)),
            const SizedBox(width: 8),
            Expanded(child: _scoreButton(3, '勉强', ChinaColors.warn)),
            const SizedBox(width: 8),
            Expanded(child: _scoreButton(4, '良好', ChinaColors.qinglv)),
            const SizedBox(width: 8),
            Expanded(child: _scoreButton(5, '简单', ChinaColors.daiLan)),
          ],
        ),
      ],
    );
  }

  Widget _scoreButton(int quality, String label, Color color) {
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: color),
      onPressed: () => _score(quality),
      child: Text(label),
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
