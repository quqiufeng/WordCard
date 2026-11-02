import 'dart:io';

import 'package:flutter/material.dart';

import '../automation/automation.dart';
import '../ffi/wordcard.dart';
import '../memo_service.dart';
import '../reader_card_export.dart';
import '../reader_library.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../tts.dart';
import '../widgets/reader_paragraph.dart';
import '../widgets/reader_chapter_list.dart';

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
  /// 正文 14 号（pt）≈ 18.7 逻辑像素；中英同号，可手动增减。
  double _bodyFontSize = 18.7;

  final ScrollController _scroll = ScrollController();
  final Map<String, WordDef> _defs = {};

  late int _chapterIndex;
  List<ReaderParagraph> _paragraphs = const [];
  List<String?> _translations = const [];
  final Set<int> _loading = {};
  int _generation = 0;
  bool _showChapters = true;
  double _chapterWidth = 320;
  String _bodyFont = AppFonts.tsangerJinKai;
  bool _exporting = false;
  bool _casting = false;

  ReaderChapter get _chapter => widget.book.chapters[_chapterIndex];

  void _setBodyFontSize(double delta) {
    setState(() {
      _bodyFontSize =
          (_bodyFontSize + delta).clamp(12.0, 36.0).toDouble();
    });
    _syncState();
  }

  void _setBodyFont(String family) {
    setState(() => _bodyFont = family);
    _syncState();
  }

  void _setChapters(bool show) {
    setState(() => _showChapters = show);
    _syncState();
  }

  String get _tag => 'book:${widget.book.title}';

  bool get _isToc => _chapter.title.trim().toLowerCase().contains(
        'table of contents',
      );


  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<CardExportResult?> _exportCardImage({bool toast = true}) async {
    if (_exporting) return null;
    setState(() => _exporting = true);
    try {
      final result = await ReaderCardExporter(
        bookTitle: widget.book.title,
        chapterTitle: _chapter.title,
        paragraphs: _paragraphs,
        translations: _translations,
      ).export();
      if (toast) _toast(result.message);
      return result;
    } catch (e) {
      if (toast) _toast('导出失败：$e');
      return null;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _kindleSlug() {
    final base = widget.book.slug
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return base.isEmpty ? 'wordcard_book' : base;
  }

  Future<bool> _castToKindle({bool toast = true}) async {
    if (_casting) return false;
    setState(() => _casting = true);
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final tmp = File('$home/.cache/wordcard/kindle_${_kindleSlug()}.txt');
    try {
      tmp.parent.createSync(recursive: true);
      final buf = StringBuffer();
      for (final chapter in widget.book.chapters) {
        if (RegExp(r'扉页|版权|目录|主要人物|书名|CIP|出版')
            .hasMatch(chapter.title)) {
          continue;
        }
        final ps = await ReaderLibrary.instance.loadChapterAsync(chapter);
        for (final p in ps) {
          final t = p.text.trim();
          if (t.isEmpty) continue;
          buf.writeln(t);
          buf.writeln();
        }
      }
      if (buf.isEmpty) throw StateError('当前书没有可推送的正文');
      tmp.writeAsStringSync(buf.toString());

      final kx = Platform.environment['KX'] ??
          '$home/.local/bin/kx';
      final name = 'wc_${_kindleSlug()}';
      final remote = '/mnt/us/ui/books/$name.txt';
      final scp = await Process.run(
        kx,
        ['scp', '-O', tmp.path, 'kindle:$remote'],
      ).timeout(const Duration(seconds: 60));
      if (scp.exitCode != 0) {
        throw StateError((scp.stderr as String).trim());
      }
      final cmd = 'printf \'open_book("$name", 1)\\n\' > /tmp/ui.cmd';
      final ssh = await Process.run(kx, ['ssh', 'kindle', cmd])
          .timeout(const Duration(seconds: 30));
      if (ssh.exitCode != 0) {
        throw StateError((ssh.stderr as String).trim());
      }
      if (toast) {
        _toast('已投屏到阅读器：$name（${widget.book.chapters.length} 章）');
      }
      return true;
    } catch (e) {
      if (toast) _toast('投屏失败：$e');
      return false;
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
      if (mounted) setState(() => _casting = false);
    }
  }

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
    a.register('reader.export', () {
      _exportCardImage();
    });
    a.register('reader.prevChapter', () => _stepChapter(-1));
    a.register('reader.nextChapter', () => _stepChapter(1));
    a.register('reader.toggleChapters', () => _setChapters(!_showChapters));
    a.registerFn('reader.state', (_) => _state());
    a.registerFn('reader.toggleChapters', (_) {
      _setChapters(!_showChapters);
      return _showChapters;
    });
    a.registerFn('reader.setFontSize', (args) {
      final size = (args['size'] as num?)?.toDouble();
      if (size == null) return false;
      setState(() {
        _bodyFontSize = size.clamp(12.0, 36.0).toDouble();
      });
      _syncState();
      return _bodyFontSize;
    });
    a.registerFn('reader.setFont', (args) {
      final f = '${args['family'] ?? ''}';
      if (f == 'tsanger' || f == 'TsangerJinKai') {
        _setBodyFont(AppFonts.tsangerJinKai);
      } else if (f == 'maple' || f == 'MapleMonoNF') {
        _setBodyFont(AppFonts.mapleMono);
      } else {
        return false;
      }
      return _bodyFont;
    });
    a.registerFn('reader.setChapterWidth', (args) {
      final w = (args['width'] as num?)?.toDouble();
      if (w == null) return false;
      setState(() => _chapterWidth = w.clamp(220.0, 560.0).toDouble());
      _syncState();
      return _chapterWidth;
    });
    a.registerFn('reader.exportCard', (_) async {
      final result = await _exportCardImage(toast: false);
      return result?.toJson();
    });
    a.registerFn('reader.castToKindle', (_) => _castToKindle(toast: false));
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
        'fontSize': _bodyFontSize,
        'fontFamily': _bodyFont,
        'chapterWidth': _chapterWidth,
        'chaptersShown': _showChapters,
        'exporting': _exporting,
        'casting': _casting,
        'tag': _tag,
      };

  void _syncState() {
    Automation.instance.updateState(_state());
  }

  Future<void> _loadChapter(int index) async {
    if (!mounted) return;
    final clamped = index.clamp(0, widget.book.chapters.length - 1);
    final chapter = widget.book.chapters[clamped];
    final gen = ++_generation;
    List<ReaderParagraph> paragraphs;
    try {
      paragraphs = await ReaderLibrary.instance.loadChapterAsync(chapter);
    } catch (_) {
      paragraphs = ReaderLibrary.instance.loadChapter(chapter);
    }
    if (!mounted || gen != _generation) return;
    final translations = List<String?>.filled(paragraphs.length, null);
    for (var i = 0; i < paragraphs.length; i++) {
      translations[i] =
          ReaderLibrary.instance.cachedTranslation(paragraphs[i].text);
    }
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
          PopupMenuButton<String>(
            tooltip: '正文字体',
            initialValue: _bodyFont,
            onSelected: (v) => _setBodyFont(v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: AppFonts.tsangerJinKai,
                child: Text('仓耳今楷'),
              ),
              PopupMenuItem(
                value: AppFonts.mapleMono,
                child: Text('Maple Mono'),
              ),
            ],
          ),
          IconButton(
            tooltip: '减小字号（${_bodyFontSize.toStringAsFixed(1)}）',
            icon: const Icon(Icons.text_decrease),
            onPressed: _bodyFontSize <= 12
                ? null
                : () => _setBodyFontSize(-1.5),
          ),
          IconButton(
            tooltip: '增大字号（${_bodyFontSize.toStringAsFixed(1)}）',
            icon: const Icon(Icons.text_increase),
            onPressed: _bodyFontSize >= 36
                ? null
                : () => _setBodyFontSize(1.5),
          ),
          IconButton(
            tooltip: _showChapters ? '隐藏目录' : '显示目录',
            icon: Icon(_showChapters ? Icons.toc : Icons.menu_book_outlined),
            onPressed: () => _setChapters(!_showChapters),
          ),
          IconButton(
            tooltip: '投屏到 Kindle 阅读器',
            icon: _casting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cast),
            onPressed: _casting ? null : _castToKindle,
          ),
          IconButton(
            tooltip: '导出当前页为图片',
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.image_outlined),
            onPressed: _exporting ? null : _exportCardImage,
          ),
          IconButton(
            tooltip: '翻译本章',
            icon: const Icon(Icons.translate),
            onPressed: _translateChapter,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              (constraints.maxWidth * 0.6).clamp(220.0, 560.0).toDouble();
          final width = _chapterWidth.clamp(220.0, maxWidth).toDouble();
          return Row(
            children: [
              if (_showChapters) ...[
                SizedBox(
                  width: width,
                  child: ReaderChapterList(
                    chapters: widget.book.chapters,
                    selectedIndex: _chapterIndex,
                    onSelect: _loadChapter,
                    onHide: () => _setChapters(false),
                  ),
                ),
                _resizeHandle(maxWidth),
              ] else
                SizedBox(
                  width: 36,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: IconButton(
                        tooltip: '显示目录',
                        icon: const Icon(Icons.keyboard_double_arrow_right,
                            size: 20),
                        onPressed: () => _setChapters(true),
                      ),
                    ),
                  ),
                ),
              Expanded(child: _reader()),
            ],
          );
        },
      ),
    );
  }

  Widget _resizeHandle(double maxWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => setState(() {
          _chapterWidth = (_chapterWidth + d.delta.dx)
              .clamp(220.0, maxWidth)
              .toDouble();
        }),
        onHorizontalDragEnd: (_) => _syncState(),
        child: const VerticalDivider(
          width: 9,
          thickness: 1,
          color: Kami.hairline,
        ),
      ),
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
    return ReaderParagraphView(
      paragraph: p,
      translation: _translations[i],
      loading: _loading.contains(i),
      isToc: _isToc,
      fontFamily: _bodyFont,
      fontSize: _bodyFontSize,
      onWordTap: _showWord,
      onTranslate: () => _translate(i),
      onSpeak: () => TtsService.instance.speak(p.text),
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
