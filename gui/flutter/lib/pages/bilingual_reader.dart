import 'package:flutter/material.dart';

import '../automation/automation.dart';
import '../ffi/wordcard.dart';
import '../memo_service.dart';
import '../reader_library.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../tts.dart';
import '../widgets/clickable_text.dart';

/// 双语阅读页：段间对照（英文原文 + 按需生成的中文译文），点词查词，
/// 可把生词加入该书对应的记忆任务（`book:<书名>`）。
class BilingualReaderScreen extends StatefulWidget {
  const BilingualReaderScreen({
    super.key,
    required this.engine,
    required this.book,
  });

  final WordCardEngine engine;
  final ReaderBook book;

  @override
  State<BilingualReaderScreen> createState() => _BilingualReaderScreenState();
}

class _BilingualReaderScreenState extends State<BilingualReaderScreen> {
  /// 正文 14 号（pt）≈ 18.7 逻辑像素；中英同号。
  static const double _bodyFontSize = 18.7;

  final ScrollController _scroll = ScrollController();
  final Map<String, WordDef> _defs = {};

  late int _chapterIndex;
  List<ReaderParagraph> _paragraphs = const [];
  List<String?> _translations = const [];
  final Set<int> _loading = {};
  int _generation = 0;
  bool _showChapters = true;

  ReaderChapter get _chapter => widget.book.chapters[_chapterIndex];

  String get _tag => 'book:${widget.book.title}';

  @override
  void initState() {
    super.initState();
    _chapterIndex = ReaderLibrary.instance
        .progressOf(widget.book.slug)
        .clamp(0, widget.book.chapters.length - 1);
    TtsService.instance.start();
    _registerAutomation();
    _loadChapter(_chapterIndex);
  }

  @override
  void dispose() {
    Automation.instance.updateState({'page': '阅读', 'book': widget.book.title});
    _scroll.dispose();
    super.dispose();
  }

  void _registerAutomation() {
    final a = Automation.instance;
    a.register('reader.translateChapter', _translateChapter);
    a.register('reader.prevChapter', () => _stepChapter(-1));
    a.register('reader.nextChapter', () => _stepChapter(1));
    a.register('reader.toggleChapters',
        () => setState(() => _showChapters = !_showChapters));
    a.registerFn('reader.state', (_) => _state());
    a.registerFn('reader.chapter', (args) {
      final index = (args['index'] as num?)?.toInt();
      if (index == null) return false;
      _loadChapter(index);
      return true;
    });
    a.registerFn('reader.translate', (args) {
      if (args['all'] == true) {
        _translateChapter();
        return true;
      }
      final index = (args['index'] as num?)?.toInt();
      if (index == null || index < 0 || index >= _paragraphs.length) {
        return false;
      }
      _translate(index);
      return true;
    });
  }

  Map<String, dynamic> _state() => {
        'page': 'reader',
        'slug': widget.book.slug,
        'book': widget.book.title,
        'chapter': _chapterIndex,
        'chapterTitle': _chapter.title,
        'chapters': widget.book.chapters.length,
        'paragraphs': _paragraphs.length,
        'translated': _translations.where((z) => z != null).length,
        'tag': _tag,
      };

  void _syncState() {
    Automation.instance.updateState(_state());
  }

  void _loadChapter(int index) {
    if (!mounted) return;
    final clamped = index.clamp(0, widget.book.chapters.length - 1);
    final chapter = widget.book.chapters[clamped];
    final paragraphs = ReaderLibrary.instance.loadChapter(chapter);
    final translations = List<String?>.filled(paragraphs.length, null);
    for (var i = 0; i < paragraphs.length; i++) {
      translations[i] =
          ReaderLibrary.instance.cachedTranslation(paragraphs[i].text);
    }
    _generation++;
    setState(() {
      _chapterIndex = clamped;
      _paragraphs = paragraphs;
      _translations = translations;
      _loading.clear();
    });
    ReaderLibrary.instance.saveProgress(widget.book.slug, clamped);
    _syncState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _stepChapter(int delta) {
    final next = _chapterIndex + delta;
    if (next < 0 || next >= widget.book.chapters.length) return;
    _loadChapter(next);
  }

  void _translate(int index) {
    if (!mounted) return;
    if (index < 0 || index >= _paragraphs.length) return;
    final p = _paragraphs[index];
    if (p.isChinese || _translations[index] != null) return;
    if (_loading.contains(index)) return;
    setState(() => _loading.add(index));
    final gen = _generation;
    MemoService.instance.translateText(p.text, (zh) {
      final t = zh.trim();
      if (t.isNotEmpty) {
        ReaderLibrary.instance.rememberTranslation(p.text, t);
      }
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading.remove(index);
        if (t.isNotEmpty) _translations[index] = t;
      });
      _syncState();
    });
  }

  void _translateChapter() {
    if (!mounted) return;
    var queued = 0;
    for (var i = 0; i < _paragraphs.length; i++) {
      if (_paragraphs[i].isChinese) continue;
      if (_translations[i] != null) continue;
      if (_loading.contains(i)) continue;
      _translate(i);
      queued++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(queued == 0 ? '本章译文已齐' : '已加入翻译队列：$queued 段（本地 LLM 逐段生成）'),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _showWord(String word) async {
    final key = word.toLowerCase();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Kami.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _WordSheet(
        engine: widget.engine,
        tag: _tag,
        bookTitle: widget.book.title,
        word: key,
        cached: _defs[key],
        onDef: (def) => _defs[key] = def,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Kami.parchment,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontFamily: AppFonts.tsangerJinKai,
              fontSize: 19,
              fontWeight: FontWeight.w500,
              color: Kami.ink),
        ),
        actions: [
          IconButton(
            tooltip: _showChapters ? '隐藏目录' : '显示目录',
            icon: Icon(_showChapters ? Icons.toc : Icons.menu_book_outlined),
            onPressed: () => setState(() => _showChapters = !_showChapters),
          ),
          IconButton(
            tooltip: '翻译本章',
            icon: const Icon(Icons.translate),
            onPressed: _translateChapter,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          if (_showChapters) ...[
            SizedBox(width: 250, child: _chapterList()),
            const VerticalDivider(width: 1, color: Kami.hairline),
          ],
          Expanded(child: _reader()),
        ],
      ),
    );
  }

  Widget _chapterList() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            '目录 · ${widget.book.chapters.length} 章',
            style: theme.textTheme.bodySmall?.copyWith(color: Kami.muted),
          ),
        ),
        const Divider(height: 1, color: Kami.hairline),
        Expanded(
          child: ListView.builder(
            primary: false,
            itemCount: widget.book.chapters.length,
            itemBuilder: (context, i) {
              final c = widget.book.chapters[i];
              final selected = i == _chapterIndex;
              return ListTile(
                dense: true,
                selected: selected,
                selectedTileColor: Kami.tint,
                leading: SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? Kami.inkBlue : Kami.faint,
                    ),
                  ),
                ),
                title: Text(
                  c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.tsangerJinKai,
                    fontSize: 14,
                    height: 1.35,
                    color: selected ? Kami.inkBlue : Kami.ink,
                  ),
                ),
                subtitle: Text('${c.pages.length} 页',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Kami.faint)),
                onTap: () => _loadChapter(i),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _reader() {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 24, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '第 ${_chapterIndex + 1} / ${widget.book.chapters.length} 章',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Kami.faint),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _chapter.title,
                      style: const TextStyle(
                          fontFamily: AppFonts.tsangerJinKai,
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          color: Kami.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: '上一章',
                icon: const Icon(Icons.chevron_left),
                onPressed: _chapterIndex == 0 ? null : () => _stepChapter(-1),
              ),
              IconButton(
                tooltip: '下一章',
                icon: const Icon(Icons.chevron_right),
                onPressed: _chapterIndex == widget.book.chapters.length - 1
                    ? null
                    : () => _stepChapter(1),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Kami.hairline),
        Expanded(
          child: _paragraphs.isEmpty
              ? Center(
                  child: Text('这一章没有可显示的正文',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Kami.muted)),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(4, 8, 8, 40),
                  itemCount: _paragraphs.length,
                  itemBuilder: (context, i) => _paragraph(i),
                ),
        ),
      ],
    );
  }

  Widget _paragraph(int i) {
    final p = _paragraphs[i];
    final theme = Theme.of(context);
    if (p.heading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 6),
        child: Text(
          p.text,
          style: const TextStyle(
              fontFamily: AppFonts.tsangerJinKai,
              fontSize: 21,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: Kami.ink),
        ),
      );
    }

    final zh = _translations[i];
    final loading = _loading.contains(i);
    final canTranslate = !p.isChinese;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClickableText(
                  p.text,
                  onWordTap: _showWord,
                  style: const TextStyle(
                      fontFamily: AppFonts.tsangerJinKai,
                      fontSize: _bodyFontSize,
                      height: 1.8,
                      color: Kami.ink),
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  if (canTranslate)
                    _iconAction(
                      tooltip: loading ? '翻译中…' : '翻译本段',
                      icon: loading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.6))
                          : Icon(
                              zh == null
                                  ? Icons.translate_outlined
                                  : Icons.translate,
                              size: 18,
                              color: zh == null ? Kami.faint : Kami.inkBlue,
                            ),
                      color: zh == null ? Kami.faint : Kami.inkBlue,
                      onTap: loading ? null : () => _translate(i),
                    ),
                  if (!p.isChinese)
                    _iconAction(
                      tooltip: '朗读本段',
                      icon: const Icon(Icons.volume_up_outlined,
                          size: 18, color: Kami.faint),
                      color: Kami.faint,
                      onTap: () => TtsService.instance.speak(p.text),
                    ),
                ],
              ),
            ],
          ),
          if (zh != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8, right: 42),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0x661B365D), width: 2),
                ),
              ),
              child: Text(
                zh,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: AppFonts.tsangerJinKai,
                  fontSize: _bodyFontSize,
                  height: 1.8,
                  color: Kami.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconAction({
    required String tooltip,
    required Widget icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: icon,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
      onPressed: onTap,
    );
  }
}

/// 点词后的查词卡片：ECDICT / LLM 释义 + 加入当前书的任务。
class _WordSheet extends StatefulWidget {
  const _WordSheet({
    required this.engine,
    required this.tag,
    required this.bookTitle,
    required this.word,
    required this.onDef,
    this.cached,
  });

  final WordCardEngine engine;
  final String tag;
  final String bookTitle;
  final String word;
  final WordDef? cached;
  final void Function(WordDef def) onDef;

  @override
  State<_WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<_WordSheet> {
  WordDef? _def;
  bool _loading = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _def = widget.cached;
    if (_def == null) _lookup();
  }

  void _lookup() {
    setState(() => _loading = true);
    MemoService.instance.lookup(widget.word, (def) {
      if (!mounted) return;
      widget.onDef(def);
      setState(() {
        _loading = false;
        _def = def;
      });
    });
  }

  void _add() {
    final def = _def;
    final word = (def?.base.isNotEmpty ?? false) ? def!.base : widget.word;
    final existing = widget.engine.itemIdByQuestion(word);
    if (existing != null) {
      final item = widget.engine.itemById(existing);
      setState(() {
        _message = item == null
            ? '这个单词已在词库中'
            : '这个单词已在「${_taskLabel(item.tagsText)}」中';
      });
      return;
    }
    final answer = def?.display ?? '';
    widget.engine.addItem(
      question: word,
      answer: answer,
      hint: def?.phonetic ?? '',
      category: 1,
      tags: widget.tag,
    );
    widget.engine.save();
    setState(() => _message = '已加入《${widget.bookTitle}》任务');
  }

  static String _taskLabel(String tag) {
    if (tag.startsWith('book:')) return tag.substring(5);
    if (tag.startsWith('dict:')) return '词表 ${tag.substring(5)}';
    if (tag.startsWith('custom:')) return tag.substring(7);
    if (tag.isEmpty) return '未分类';
    return tag;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final def = _def;
    final word = (def?.base.isNotEmpty ?? false) ? def!.base : widget.word;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                word,
                style: const TextStyle(
                    fontFamily: AppFonts.tsangerJinKai,
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    color: Kami.ink),
              ),
              const SizedBox(width: 10),
              if (def != null && def.phonetic.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('/${def.phonetic}/',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Kami.muted)),
                ),
              const Spacer(),
              IconButton(
                tooltip: '朗读',
                icon: const Icon(Icons.volume_up_outlined, color: Kami.inkBlue),
                onPressed: () => TtsService.instance.speak(word),
              ),
            ],
          ),
          if (def != null && def.base.isNotEmpty)
            Text('原形 · ${def.base}',
                style: theme.textTheme.bodySmall?.copyWith(color: Kami.faint)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.8)),
                  SizedBox(width: 10),
                  Text('查词中…'),
                ],
              ),
            )
          else if (def == null || def.def.isEmpty)
            Text('未查到释义', style: theme.textTheme.bodyMedium)
          else ...[
            Text(
              def.display,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontFamily: AppFonts.tsangerJinKai, height: 1.6),
            ),
            if (def.en.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(def.en,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Kami.muted, height: 1.5)),
            ],
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _loading ? null : _add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('加入读书任务'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _message,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: _message.startsWith('已')
                          ? const Color(0xFF2E8B57)
                          : Kami.muted),
                ),
              ),
              TextButton(
                onPressed: _loading ? null : _lookup,
                child: const Text('重查'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
