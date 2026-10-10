import 'dart:math';

import 'package:flutter/material.dart';

import '../ffi/wordcard.dart';
import '../theme/app_theme.dart';
import '../tts.dart';

enum _Phase { ready, running, done }

class _ExamItem {
  _ExamItem(this.id, this.word, this.answer);
  final int id;
  final String word;
  final String answer;
}

/// 听写考试：随机取任务词表的一半，逐词朗读（间隔 8 秒），
/// 结束后列出全部听写词条及中文翻译。
class DictationExamPage extends StatefulWidget {
  const DictationExamPage({
    super.key,
    required this.engine,
    required this.itemIds,
    this.title = '听写',
  });

  final WordCardEngine engine;
  final List<int> itemIds;
  final String title;

  @override
  State<DictationExamPage> createState() => _DictationExamPageState();
}

class _DictationExamPageState extends State<DictationExamPage> {
  static const int _gap = 8; // 每个词的间隔秒数

  final List<_ExamItem> _items = [];
  _Phase _phase = _Phase.ready;
  int _index = 0;
  int _countdown = _gap;
  bool _aborted = false;

  @override
  void initState() {
    super.initState();
    final all = widget.itemIds
        .map(widget.engine.itemById)
        .whereType<ItemEntry>()
        .map((e) => _ExamItem(e.id, e.questionText, e.answerText))
        .toList();
    all.shuffle(Random());
    final half = (all.length / 2).ceil().clamp(0, all.length);
    _items.addAll(all.take(half));
    TtsService.instance.start();
  }

  Future<void> _run() async {
    setState(() {
      _phase = _Phase.running;
      _index = 0;
      _aborted = false;
    });
    for (var i = 0; i < _items.length; i++) {
      if (_aborted || !mounted) break;
      setState(() => _index = i);
      TtsService.instance.speak(_items[i].word);
      for (var s = _gap; s > 0; s--) {
        if (_aborted || !mounted) break;
        setState(() => _countdown = s);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (mounted) setState(() => _phase = _Phase.done);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: switch (_phase) {
        _Phase.ready => _ready(theme),
        _Phase.running => _running(theme),
        _Phase.done => _done(theme),
      },
    );
  }

  Widget _ready(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.keyboard_alt_outlined,
              size: 56, color: ChinaColors.daiLan),
          const SizedBox(height: 16),
          Text('本次听写 ${_items.length} 个（随机一半）',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('每 8 秒读一个，请准备好纸笔',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: ChinaColors.muted)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _items.isEmpty ? null : _run,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始听写'),
          ),
        ],
      ),
    );
  }

  Widget _running(ThemeData theme) {
    final word = _items.isEmpty ? '' : _items[_index].word;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text('第 ${_index + 1} / ${_items.length} 个',
              style: theme.textTheme.titleMedium),
          const Expanded(
            child: Center(
              child: Text('🔊',
                  style: TextStyle(fontSize: 64)), // 正在朗读，不显示单词
            ),
          ),
          SizedBox(
            height: 120,
            width: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 120,
                  width: 120,
                  child: CircularProgressIndicator(
                    value: _countdown / _gap,
                    strokeWidth: 6,
                    backgroundColor: ChinaColors.border,
                  ),
                ),
                Text('$_countdown',
                    style: theme.textTheme.displaySmall
                        ?.copyWith(color: ChinaColors.ink)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('（写完请等待下一词）',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: ChinaColors.muted)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => TtsService.instance.speak(word),
                icon: const Icon(Icons.replay),
                label: const Text('重听'),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _aborted = true),
                icon: const Icon(Icons.stop),
                label: const Text('结束'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _done(ThemeData theme) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: ChinaColors.shuangdi,
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: ChinaColors.qinglv),
              const SizedBox(width: 8),
              Text('听写完成 · 共 ${_items.length} 个',
                  style: theme.textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _run,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('再来'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final it = _items[i];
              return ListTile(
                leading: Text('${i + 1}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: ChinaColors.dim)),
                title: Text(it.word,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: ChinaColors.ink)),
                subtitle: Text(it.answer.isEmpty ? '—' : it.answer,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: ChinaColors.muted)),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回任务'),
            ),
          ),
        ),
      ],
    );
  }
}
