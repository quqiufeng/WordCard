import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ffi/wordcard.dart';
import '../state/study_session.dart';
import '../theme/app_theme.dart';
import '../automation/automation.dart';
import '../tts.dart';
import '../memo_service.dart';
import '../widgets/flash_card.dart';
import '../widgets/stats_widget.dart';
import 'import_page.dart';
import 'tasks_page.dart';

/// 主页面：初始化引擎与会话，承载可折叠侧栏布局。
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  static const _titles = ['复习', '任务', '统计', '导入'];
  static const _navIds = ['review', 'queue', 'stats', 'import'];
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
  bool _showNav = true;
  bool _dictationFlag = false;

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
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: _showNav ? 220 : 0,
          child: _showNav ? _nav(context) : const SizedBox.shrink(),
        ),
        if (_showNav) const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              _header(context),
              Expanded(child: _content(session)),
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
            tooltip: _showNav ? '隐藏侧栏 (nav.toggle)' : '显示侧栏 (nav.toggle)',
            icon: Icon(_showNav ? Icons.menu_open : Icons.menu),
            onPressed: () => Automation.instance.invoke('nav.toggle'),
          ),
          Text(_titles[_index], style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _content(StudySession session) => switch (_index) {
        0 => _ReviewPage(
            session: session,
            startDictation: _dictationFlag,
            onDictationConsumed: () =>
                setState(() => _dictationFlag = false),
          ),
        1 => TasksPage(
            engine: _engine!,
            onSpeak: (t) => TtsService.instance.speak(t),
            onDictate: _startTaskDictation,
          ),
        2 => _StatsPage(session: session, engine: _engine!),
        _ => ImportPage(engine: _engine!),
      };

  /// 用某任务的整份词表开始听写。
  void _startTaskDictation(List<int> ids) {
    if (ids.isEmpty) return;
    _session?.startItems(ids);
    setState(() {
      _index = 0;
      _dictationFlag = true;
    });
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
  const _ReviewPage({
    required this.session,
    this.startDictation = false,
    this.onDictationConsumed,
  });

  final StudySession session;
  final bool startDictation;
  final VoidCallback? onDictationConsumed;

  @override
  State<_ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<_ReviewPage> {
  StudySession get s => widget.session;
  final Set<String> _memoRequested = {};
  final Set<String> _paraRequested = {};
  int _pending = 0;

  bool _dictation = false;
  bool _revealed = false;
  bool _correct = false;
  int? _lastCardId;
  final TextEditingController _input = TextEditingController();

  void _beginLoad() {
    if (mounted) setState(() => _pending++);
  }

  void _endLoad() {
    if (mounted) setState(() => _pending = _pending > 0 ? _pending - 1 : 0);
  }

  static String _truncUtf8(String s, int maxBytes) {
    final b = utf8.encode(s);
    if (b.length <= maxBytes) return s;
    return utf8.decode(b.sublist(0, maxBytes), allowMalformed: true);
  }

  @override
  void initState() {
    super.initState();
    if (widget.startDictation) {
      _dictation = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        TtsService.instance.speak(s.current?.question ?? '');
        widget.onDictationConsumed?.call();
      });
    }
    final a = Automation.instance;
    a.register('review.flip', () {
      s.flip();
      final w = s.current?.question;
      if (w != null) TtsService.instance.speak(w);
    });
    a.register('review.know', _know);
    a.register('review.dontKnow', _dontKnow);
    a.register('review.restart', () => s.start());
    a.register('review.dictation', () {
      setState(() {
        _dictation = !_dictation;
        _revealed = false;
        _correct = false;
        _input.clear();
      });
      if (_dictation) TtsService.instance.speak(s.current?.question ?? '');
    });
    a.register('review.check', _check);
    a.register('review.speakParagraph', () {
      final c = s.current;
      if (c == null) return;
      final cjk = RegExp(r'[\u4e00-\u9fff]');
      final latin = RegExp(r'[A-Za-z]');
      final buf = <String>[];
      for (final l in c.explanation.split('\n')) {
        final t = l.trim();
        if (t.isEmpty || t.startsWith('【')) continue;
        if (latin.hasMatch(t) && !cjk.hasMatch(t)) buf.add(t);
      }
      if (buf.isNotEmpty) {
        TtsService.instance.speak(buf.join(' '));
      }
    });
    TtsService.instance.start(); // 预加载 TTS 模型
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.startDictation && !oldWidget.startDictation && !_dictation) {
      setState(() => _dictation = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        TtsService.instance.speak(s.current?.question ?? '');
        widget.onDictationConsumed?.call();
      });
    }
  }

  /// 听写判分：忽略大小写/空格/标点。
  void _check() {
    final card = s.current;
    if (card == null) return;
    String norm(String x) =>
        x.toLowerCase().replaceAll(RegExp(r"[^a-z0-9\u4e00-\u9fff]+"), '');
    final ok =
        _input.text.trim().isNotEmpty && norm(_input.text) == norm(card.question);
    setState(() {
      _revealed = true;
      _correct = ok;
    });
  }

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

  /// 当前卡片若无「用法」助记，则按需向常驻服务请求并回填。
  void _ensureMemo() {
    if (!mounted) return;
    final card = s.current;
    if (card == null) return;
    if (card.explanation.startsWith('【用法】')) return;
    final word = card.question;
    if (word.isEmpty || _memoRequested.contains(word)) return;
    _memoRequested.add(word);
    final ctx = card.explanation.split('\n').first;
    _beginLoad();
    MemoService.instance.request(word, ctx, (memo) {
      _endLoad();
      if (!mounted || memo.isEmpty) return;
      final id = s.engine.itemIdByQuestion(word);
      if (id == null) return;
      final cur = s.engine.itemById(id);
      final old = cur?.explanationText ?? '';
      if (old.startsWith('【用法】')) return;
      s.engine.updateItemExplanation(id, _truncUtf8('【用法】$memo\n$old', 1000));
      s.engine.save();
      if (mounted) setState(() {});
    });
  }

  /// 卡片若有英文段落但无中文译文，按需翻译并回填。
  void _ensureParaZh() {
    if (!mounted) return;
    final card = s.current;
    if (card == null) return;
    final expl = card.explanation;
    if (expl.contains('【段落】')) return; // 导入时已带译文
    final cjk = RegExp(r'[\u4e00-\u9fff]');
    final latin = RegExp(r'[A-Za-z]');
    final lines = expl
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final hasZh =
        lines.any((l) => !l.startsWith('【用法】') && cjk.hasMatch(l));
    if (hasZh) return;
    final eng = lines
        .where((l) => latin.hasMatch(l) && !cjk.hasMatch(l))
        .join(' ');
    if (eng.isEmpty || _paraRequested.contains(card.question)) return;
    _paraRequested.add(card.question);
    _beginLoad();
    MemoService.instance.translateText(eng, (zh) {
      _endLoad();
      if (!mounted || zh.isEmpty) return;
      final id = s.engine.itemIdByQuestion(card.question);
      if (id == null) return;
      final cur = s.engine.itemById(id);
      final old = cur?.explanationText ?? '';
      if (old.contains(zh)) return;
      s.engine.updateItemExplanation(id, _truncUtf8('$old\n$zh', 1000));
      s.engine.save();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final cid = s.current?.itemId;
        if (cid != _lastCardId) {
          _lastCardId = cid;
          _revealed = false;
          _correct = false;
          _input.clear();
          if (_dictation && cid != null) {
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => TtsService.instance.speak(s.current?.question ?? ''));
          }
        }
        Automation.instance.updateState({
          'page': 'review',
          'total': s.total,
          'done': s.done,
          'finished': s.finished,
          'flipped': s.flipped,
          'dictation': _dictation,
          'word': s.current?.question,
          'mode': s.current?.modeName,
          'lastOverall': s.lastResult?.overall,
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureMemo();
          _ensureParaZh();
        });
        return CallbackShortcuts(
          bindings: _dictation
              ? const {}
              : {
                  // 空格 = 不会；方向右键 = 记得并下一张
                  const SingleActivator(LogicalKeyboardKey.space): () =>
                      Automation.instance.invoke('review.dontKnow'),
                  const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                      Automation.instance.invoke('review.know'),
                },
          child: Focus(
            autofocus: !_dictation,
            child: _body(context),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    if (s.finished) return _finished(context);
    final card = s.current;
    if (card == null) return _empty(context);

    return Column(
      children: [
        _dictationBar(context),
        Expanded(
          child: _dictation
              ? _dictationBody(context, card)
              : _normalBody(context, card),
        ),
      ],
    );
  }

  Widget _dictationBar(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 12, top: 4),
        child: FilterChip(
          avatar: const Icon(Icons.keyboard_alt_outlined, size: 16),
          label: const Text('听写'),
          selected: _dictation,
          onSelected: (_) =>
              Automation.instance.invoke('review.dictation'),
        ),
      ),
    );
  }

  Widget _normalBody(BuildContext context, ActiveCard card) {
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Expanded(
              child: FlashCard(
                card: card,
                flipped: s.flipped,
                onFlip: () => Automation.instance.invoke('review.flip'),
                onSpeak: (t) => TtsService.instance.speak(t),
                loading: _pending > 0,
                speaking: TtsService.instance.busy,
              ),
            ),
            const SizedBox(height: 16),
            _controls(context),
          ],
        ),
      ),
    );
  }

  Widget _dictationBody(BuildContext context, ActiveCard card) {
    final theme = Theme.of(context);
    final word = card.question;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '重听',
                    icon: const Icon(Icons.volume_up,
                        size: 56, color: ChinaColors.daiLan),
                    onPressed: () => TtsService.instance.speak(word),
                  ),
                  const SizedBox(height: 8),
                  Text('听写：写下你听到的单词/词组',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: ChinaColors.muted)),
                  const SizedBox(height: 20),
                  if (_revealed) ...[
                    Icon(_correct ? Icons.check_circle : Icons.cancel,
                        size: 48,
                        color: _correct
                            ? ChinaColors.qinglv
                            : ChinaColors.zhusha),
                    const SizedBox(height: 12),
                    Text(word,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(color: ChinaColors.daiLan)),
                    if (!_correct) ...[
                      const SizedBox(height: 6),
                      Text(
                          '你写的是：${_input.text.trim().isEmpty ? '（空）' : _input.text}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: ChinaColors.muted)),
                    ],
                  ] else
                    SizedBox(
                      width: 340,
                      child: TextField(
                        controller: _input,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge,
                        decoration: const InputDecoration(
                          hintText: '在此输入',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _check(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _revealed ? ChinaColors.daiLan : ChinaColors.qinglv,
                ),
                onPressed: () => _revealed
                    ? s.grade(_correct ? 4 : 1)
                    : _check(),
                icon: Icon(_revealed ? Icons.arrow_forward : Icons.check),
                label: Text(_revealed ? '下一张' : '检查'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: ChinaColors.orange),
              onPressed: () => Automation.instance.invoke('review.dontKnow'),
              icon: const Icon(Icons.close),
              label: const Text('不会'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: ChinaColors.qinglv),
              onPressed: () => Automation.instance.invoke('review.know'),
              icon: const Icon(Icons.check),
              label: const Text('记得'),
            ),
          ),
        ],
      ),
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
            onPressed: () => Automation.instance.invoke('review.restart'),
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

// ────────────────────────────── 统计 ──────────────────────────────

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
