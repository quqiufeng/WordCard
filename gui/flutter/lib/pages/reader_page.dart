import 'dart:io';

import 'package:flutter/material.dart';

import '../automation/automation.dart';
import '../reader_library.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';

/// 「阅读」页：本地书库（`/opt/books` 中由 import_book 解析出的书籍）。
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.onOpen});

  final void Function(ReaderBook book) onOpen;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  List<ReaderBook> _books = const [];
  bool _busy = false;
  String _log = '';
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _reload();
    Automation.instance.register('reader.import', _importBook);
  }

  void _reload() {
    final books = ReaderLibrary.instance.listBooks();
    if (mounted) setState(() => _books = books);
  }

  Future<String?> _pickFile() async {
    final r = await ProcessRunner.zenity;
    return r;
  }

  Future<void> _importBook() async {
    if (_busy) return;
    final path = await _pickFile();
    if (path == null || !mounted) return;
    setState(() {
      _busy = true;
      _failed = false;
      _log = '正在导入 ${path.split('/').last} …';
    });
    try {
      final code = await ReaderLibrary.instance.importBook(path, onLog: (l) {
        if (!mounted) return;
        setState(() => _log = l);
      });
      if (!mounted) return;
      if (code != 0) {
        setState(() {
          _busy = false;
          _failed = true;
          _log = '导入失败（exit $code）：$_log';
        });
        return;
      }
      _reload();
      setState(() {
        _busy = false;
        _log = '已导入 ${path.split('/').last}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _log = '导入失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              const Icon(Icons.auto_stories_outlined,
                  size: 20, color: Kami.inkBlue),
              const SizedBox(width: 8),
              const Text(
                '书架',
                style: TextStyle(
                    fontFamily: AppFonts.tsangerJinKai,
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    color: Kami.ink),
              ),
              const SizedBox(width: 10),
              Text('${_books.length} 本 · 点开即可双语阅读',
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: Kami.muted)),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _importBook,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.add, size: 18),
                label: const Text('导入电子书'),
              ),
            ],
          ),
        ),
        if (_log.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _failed ? const Color(0xFFF7ECE9) : Kami.surface,
              border: Border.all(
                  color: _failed ? const Color(0xFFE3C3BC) : Kami.hairline),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _log,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: _failed ? Kami.error : Kami.muted),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: _books.isEmpty
              ? _empty(theme)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth > 1100
                        ? 3
                        : (constraints.maxWidth > 720 ? 2 : 1);
                    return GridView.builder(
                      padding: const EdgeInsets.all(20),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        mainAxisExtent: 196,
                      ),
                      itemCount: _books.length,
                      itemBuilder: (context, i) => _bookCard(_books[i]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _empty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.menu_book_outlined, size: 52, color: Kami.faint),
          const SizedBox(height: 12),
          Text('书架还是空的', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('导入 EPUB / MOBI / AZW3 / PDF，解析后即可中英对照阅读',
              style: theme.textTheme.bodySmall?.copyWith(color: Kami.muted)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _importBook,
            icon: const Icon(Icons.add),
            label: const Text('导入第一本书'),
          ),
        ],
      ),
    );
  }

  Widget _bookCard(ReaderBook book) {
    final theme = Theme.of(context);
    final progress = ReaderLibrary.instance.progressOf(book.slug);
    final current = progress.clamp(0, book.chapters.length - 1);
    final chapter = book.chapters[current];
    return Material(
      color: Kami.surface,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Kami.hairline),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpen(book),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: AppFonts.tsangerJinKai,
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                          color: Kami.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_outward, size: 16, color: Kami.faint),
                ],
              ),
              if (book.author.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: Kami.muted)),
              ],
              const Spacer(),
              Text(
                '${book.chapters.length} 章 · ${book.pages} 页',
                style: theme.textTheme.bodySmall?.copyWith(color: Kami.muted),
              ),
              const SizedBox(height: 6),
              Container(height: 2, color: Kami.hairline),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      progress > 0
                          ? '继续：${chapter.title}'
                          : '从「${chapter.title}」开始',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Kami.inkBlue),
                    ),
                  ),
                  Text(
                    '第 ${current + 1}/${book.chapters.length} 章',
                    style:
                        theme.textTheme.labelSmall?.copyWith(color: Kami.faint),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选择电子书文件（zenity）。
abstract final class ProcessRunner {
  static Future<String?> get zenity async {
    final r = await Process.run('zenity', [
      '--file-selection',
      '--title=导入电子书',
      '--file-filter=电子书 | *.epub *.mobi *.azw *.azw3 *.pdf',
      '--file-filter=所有文件 | *',
    ]);
    if (r.exitCode != 0) return null;
    final path = (r.stdout as String).trim();
    return path.isEmpty ? null : path;
  }
}
