import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ffi/wordcard.dart';
import '../theme/app_theme.dart';
import '../widgets/memory_curve.dart';
import 'dictation_exam.dart';

/// 记忆任务：每个电子书/词表导入 = 一个任务（在 items 的 tags 之上分组的一层）。
/// 点任务 → 翻页查看其所有单词；任务可删除 / 听写整份 / 学习。
class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.engine,
    required this.userId,
    this.onSpeak,
    this.onStudy,
  });

  final WordCardEngine engine;
  final int userId;
  final void Function(String text)? onSpeak;
  final void Function(List<int> itemIds, String name)? onStudy;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  static const _pageSize = 50;

  String? _tag;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return _tag == null ? _taskList(context) : _wordList(context, _tag!);
  }

  // ── 任务列表 ──
  Widget _taskList(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = widget.engine.tasks();
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.assignment_outlined,
                size: 48, color: ChinaColors.dim),
            const SizedBox(height: 12),
            Text('暂无记忆任务', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('去「导入」添加电子书或词表',
                style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }
    return ListView(
      primary: false,
      children: [
        for (final t in tasks)
          ListTile(
            leading: Icon(
              t.tag.startsWith('dict:')
                  ? Icons.translate_outlined
                  : (t.tag.startsWith('book:')
                      ? Icons.menu_book_outlined
                      : Icons.folder_outlined),
            ),
            title: Text(t.name),
            subtitle: Text('${t.kind} · ${t.count} 词'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: widget.onStudy == null
                      ? null
                      : () => widget.onStudy!(
                          widget.engine
                              .itemsByTag(t.tag)
                              .map((e) => e.id)
                              .toList(),
                          t.name),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('学习'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _startExam(context, t.tag, t.name),
                  icon: const Icon(Icons.keyboard_alt_outlined, size: 16),
                  label: const Text('听写'),
                ),
                IconButton(
                  tooltip: '删除任务',
                  icon: const Icon(Icons.delete_outline,
                      color: ChinaColors.zhusha),
                  onPressed: () => _confirmDelete(t),
                ),
              ],
            ),
            onTap: () => setState(() {
              _tag = t.tag;
              _page = 0;
            }),
          ),
      ],
    );
  }

  // ── 任务内单词（翻页）──
  Widget _wordList(BuildContext context, String tag) {
    final theme = Theme.of(context);
    final items = widget.engine.itemsByTag(tag);
    final pages = math.max(1, (items.length / _pageSize).ceil());
    if (_page >= pages) _page = pages - 1;
    final start = _page * _pageSize;
    final end = math.min(start + _pageSize, items.length);
    final slice = items.sublist(start, end);

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              IconButton(
                tooltip: '返回任务列表',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _tag = null),
              ),
              Expanded(
                child: Text(
                  '${_nameOf(tag)} · ${items.length} 词',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (items.isNotEmpty && widget.onStudy != null)
                IconButton(
                  tooltip: '学习这组单词',
                  icon: const Icon(Icons.play_arrow, color: ChinaColors.qinglv),
                  onPressed: () => widget.onStudy!(
                      items.map((e) => e.id).toList(), _nameOf(tag)),
                ),
              if (items.isNotEmpty)
                IconButton(
                  tooltip: '朗读当前页所有单词',
                  icon: const Icon(Icons.playlist_play),
                  onPressed: widget.onSpeak == null
                      ? null
                      : () => widget
                          .onSpeak!(slice.map((e) => e.questionText).join(', ')),
                ),
              if (items.isNotEmpty)
                IconButton(
                  tooltip: '听写整份词表',
                  icon: const Icon(Icons.keyboard_alt_outlined,
                      color: ChinaColors.daiLan),
                  onPressed: () => _startExam(context, tag, _nameOf(tag)),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('记忆曲线 · 未来 14 天复习安排',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: ChinaColors.muted)),
              const SizedBox(height: 4),
              MemoryCurve(values: _dueCurve(items, 14), height: 64),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            primary: false,
            itemCount: slice.length,
            itemBuilder: (context, i) {
              final it = slice[i];
              return ListTile(
                dense: true,
                title: Text(it.questionText),
                subtitle: Text(
                  it.answerText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                trailing: widget.onSpeak == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.volume_up_outlined, size: 18),
                        tooltip: '朗读',
                        onPressed: () => widget.onSpeak!(it.questionText),
                      ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _page > 0 ? () => setState(() => _page--) : null,
            ),
            Text('${_page + 1} / $pages'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed:
                  _page < pages - 1 ? () => setState(() => _page++) : null,
            ),
          ],
        ),
      ],
    );
  }

  List<int> _dueCurve(List<ItemEntry> items, int days) {
    final now = widget.engine.now();
    final v = List<int>.filled(days, 0);
    for (final it in items) {
      final m = widget.engine.mastery(userId: widget.userId, itemId: it.id);
      final nr = m?.nextReview ?? 0;
      final d = (nr == 0 || nr <= now)
          ? 0
          : ((nr - now) / 86400).ceil().clamp(0, days - 1);
      v[d]++;
    }
    return v;
  }

  void _startExam(BuildContext context, String tag, String name) {
    final ids = widget.engine.itemsByTag(tag).map((e) => e.id).toList();
    if (ids.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DictationExamPage(
        engine: widget.engine,
        itemIds: ids,
        title: '听写 · $name',
      ),
    ));
  }

  Future<void> _confirmDelete(TaskInfo t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('删除「${t.name}」及其 ${t.count} 个单词？'
            '（含复习记录，不可恢复）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    widget.engine.deleteItemsByTag(t.tag);
    widget.engine.save();
    if (mounted) setState(() {});
  }

  static String _nameOf(String tag) {
    if (tag.startsWith('book:')) return tag.substring(5);
    if (tag.startsWith('dict:')) return '词表 ${tag.substring(5)}';
    if (tag.isEmpty) return '(未分类)';
    return tag;
  }
}
