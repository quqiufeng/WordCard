import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../automation/automation.dart';
import '../memo_service.dart';
import '../state/study_session.dart';
import '../theme/app_theme.dart';
import '../tts.dart';
import '../widgets/flash_card.dart';

/// 记忆（复习）页：以独立路由打开（今日队列或某任务词表）。
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.session, this.title = '复习'});

  final StudySession session;
  final String title;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  StudySession get s => widget.session;
  final Set<String> _memoRequested = {};
  final Set<String> _paraRequested = {};
  int _pending = 0;

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
    final a = Automation.instance;
    a.register('review.flip', () {
      s.flip();
      final w = s.current?.question;
      if (w != null) TtsService.instance.speak(w);
    });
    a.register('review.know', _know);
    a.register('review.dontKnow', _dontKnow);
    a.register('review.restart', () => s.restart());
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
      if (buf.isNotEmpty) TtsService.instance.speak(buf.join(' '));
    });
    TtsService.instance.start();
  }

  void _know() {
    if (s.finished) {
      s.restart();
      return;
    }
    s.grade(4);
  }

  void _dontKnow() {
    if (s.finished) {
      s.restart();
      return;
    }
    s.grade(1);
  }

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

  void _ensureParaZh() {
    if (!mounted) return;
    final card = s.current;
    if (card == null) return;
    final expl = card.explanation;
    if (expl.contains('【段落】')) return;
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title),
      ),
      body: AnimatedBuilder(
        animation: s,
        builder: (context, _) {
          Automation.instance.updateState({
            'page': 'review',
            'total': s.total,
            'done': s.done,
            'finished': s.finished,
            'flipped': s.flipped,
            'word': s.current?.question,
            'mode': s.current?.modeName,
            'lastOverall': s.lastResult?.overall,
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureMemo();
            _ensureParaZh();
          });
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.space): () =>
                  Automation.instance.invoke('review.dontKnow'),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  Automation.instance.invoke('review.know'),
            },
            child: Focus(
              autofocus: true,
              child: _body(context),
            ),
          );
        },
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

  Widget _controls(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: ChinaColors.orange),
              onPressed: () => Automation.instance.invoke('review.dontKnow'),
              icon: const Icon(Icons.close),
              label: const Text('不会'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: ChinaColors.qinglv),
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
          Text('本组记忆完成！', style: theme.textTheme.titleLarge),
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
          Text('这组没有可复习的内容', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('可在「任务」里选择学习，或「导入」添加词表',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
