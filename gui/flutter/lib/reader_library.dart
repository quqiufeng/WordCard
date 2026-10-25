import 'dart:convert';
import 'dart:io';

/// 一本已解析的书（来自 `/opt/books/<slug>/chapters/*/page_*.md`）。
///
/// 解析由 `/opt/my_db` 的 `import_book` 完成，本应用只负责阅读与翻译。
final class ReaderBook {
  const ReaderBook({
    required this.slug,
    required this.title,
    required this.author,
    required this.dir,
    required this.chapters,
  });

  final String slug;
  final String title;
  final String author;
  final String dir;
  final List<ReaderChapter> chapters;

  int get pages =>
      chapters.fold(0, (sum, chapter) => sum + chapter.pages.length);
}

/// 一本书中的一章（对应 `chapters/NN-.../` 目录）。
final class ReaderChapter {
  const ReaderChapter({
    required this.index,
    required this.dirName,
    required this.title,
    required this.pages,
  });

  final int index;
  final String dirName;
  final String title;
  final List<String> pages;
}

/// 阅读页中的一个段落（英文/原文）。
final class ReaderParagraph {
  const ReaderParagraph(this.text, {this.heading = false});

  final String text;
  final bool heading;

  static final _cjk = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]');
  static final _latin = RegExp(r'[A-Za-z]');

  /// 原文已是中文时无需再翻译。
  bool get isChinese =>
      _cjk.allMatches(text).length > _latin.allMatches(text).length * 2;

  int get length => text.length;
}

/// 读取 `/opt/books` 下的书籍、章节和段落；缓存段落译文与阅读进度。
final class ReaderLibrary {
  ReaderLibrary._();

  static final ReaderLibrary instance = ReaderLibrary._();

  /// `.md` 根目录；可用 `BOOK_MD_ROOT` 覆盖（测试/迁移）。
  static String get root =>
      Platform.environment['BOOK_MD_ROOT'] ?? '/opt/books';

  static String? _appRoot() {
    for (final c in ['.', '/opt/WordCard']) {
      if (File('$c/tools/memo_server.py').existsSync()) {
        return Directory(c).absolute.path;
      }
    }
    return null;
  }

  static File? _dataFile(String name) {
    final root = _appRoot();
    if (root == null) return null;
    final dir = Directory('$root/data')..createSync(recursive: true);
    return File('${dir.path}/$name');
  }

  // ── 书架 ───────────────────────────────────────────────

  List<ReaderBook> listBooks() {
    final dir = Directory(root);
    if (!dir.existsSync()) return const [];
    final out = <ReaderBook>[];
    for (final entity in dir.listSync()) {
      if (entity is! Directory) continue;
      final chapters = _readChapters(entity);
      if (chapters.isEmpty) continue;
      if (chapters.every((c) => c.pages.isEmpty)) continue;
      final meta = _readMeta(entity.path);
      final slug = entity.path.split('/').last;
      final title = '${meta['title'] ?? ''}'.trim();
      out.add(ReaderBook(
        slug: slug,
        title: title.isEmpty ? slug : title,
        author: '${meta['author'] ?? ''}'.trim(),
        dir: entity.path,
        chapters: chapters,
      ));
    }
    out.sort((a, b) => a.title.compareTo(b.title));
    return out;
  }

  ReaderBook? bookBySlug(String slug) {
    for (final book in listBooks()) {
      if (book.slug == slug) return book;
    }
    return null;
  }

  Map<String, dynamic> _readMeta(String bookDir) {
    final f = File('$bookDir/_meta.json');
    if (!f.existsSync()) return const {};
    try {
      return json.decode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  List<ReaderChapter> _readChapters(Directory bookDir) {
    final dir = Directory('${bookDir.path}/chapters');
    if (!dir.existsSync()) return const [];
    final dirs = dir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final out = <ReaderChapter>[];
    for (final d in dirs) {
      final pages = d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .map((f) => f.path)
          .toList()
        ..sort();
      if (pages.isEmpty) continue;
      final name = d.path.split('/').last;
      out.add(ReaderChapter(
        index: out.length,
        dirName: name,
        title: _prettyChapter(name),
        pages: pages,
      ));
    }
    return out;
  }

  static String _prettyChapter(String dirName) {
    final m = RegExp(r'^(\d+)[-_]+(.*)$').firstMatch(dirName);
    var title = m?.group(2) ?? dirName;
    title = title.replaceAll('_', ' ').trim();
    return title.isEmpty ? dirName : title;
  }

  // ── 章节正文 ───────────────────────────────────────────

  /// 读取一章，清洗 Markdown 并还原段落。
  List<ReaderParagraph> loadChapter(ReaderChapter chapter) {
    final out = <ReaderParagraph>[];
    for (final path in chapter.pages) {
      final f = File(path);
      if (!f.existsSync()) continue;
      final paragraphs = _parsePage(f.readAsStringSync());
      for (final p in paragraphs) {
        if (p.text.trim().isEmpty) continue;
        if (out.isNotEmpty &&
            !out.last.heading &&
            !p.heading &&
            _continues(out.last.text, p.text)) {
          out[out.length - 1] = ReaderParagraph(_join(out.last.text, p.text));
        } else {
          out.add(p);
        }
      }
    }
    return out;
  }

  List<ReaderParagraph> _parsePage(String raw) {
    var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // YAML front matter
    if (text.startsWith('---')) {
      final end = text.indexOf('\n---', 3);
      if (end > 0) text = text.substring(end + 4);
    }
    text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    final lines = <String>[];
    for (final line in text.split('\n')) {
      final s = line.trimRight();
      final t = s.trim();
      if (t.startsWith('Page:') || t.startsWith('File:')) continue;
      if (RegExp(r'^!\[[^\]]*\]\([^)]*\)$').hasMatch(t)) continue;
      lines.add(s);
    }
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    if (lines.isEmpty) return const [];

    final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) return const [];

    final hasBlank = lines.any((l) => l.trim().isEmpty);
    if (hasBlank) return _parseByBlank(lines);

    final avg =
        nonEmpty.fold<int>(0, (n, l) => n + l.trim().length) / nonEmpty.length;
    final terminals =
        nonEmpty.where((l) => _endsSentence(l.trim())).length / nonEmpty.length;
    if (avg > 160 || terminals > 0.55) return _parseByLine(nonEmpty);
    return _parseReflow(nonEmpty);
  }

  List<ReaderParagraph> _parseByBlank(List<String> lines) {
    final out = <ReaderParagraph>[];
    final group = <String>[];
    void flush() {
      if (group.isEmpty) return;
      final joined = _joinLines(group);
      if (joined.isNotEmpty) out.addAll(_splitLong(joined));
      group.clear();
    }

    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) {
        flush();
        continue;
      }
      final h = _headingText(t);
      if (h != null) {
        flush();
        out.add(ReaderParagraph(h, heading: true));
        continue;
      }
      group.add(t);
    }
    flush();
    return out;
  }

  List<ReaderParagraph> _parseByLine(List<String> lines) {
    final out = <String>[];
    for (final raw in lines) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      final h = _headingText(t);
      if (h != null) {
        out.add('\u0001$h');
        continue;
      }
      if (out.isNotEmpty &&
          !out.last.startsWith('\u0001') &&
          _continues(out.last, t)) {
        out[out.length - 1] = _join(out.last, t);
      } else {
        out.add(t);
      }
    }
    return [
      for (final s in out)
        if (s.startsWith('\u0001'))
          ReaderParagraph(s.substring(1), heading: true)
        else
          ..._splitLong(s),
    ];
  }

  List<ReaderParagraph> _parseReflow(List<String> lines) {
    final out = <ReaderParagraph>[];
    final buf = StringBuffer();
    void flush() {
      final t = buf.toString().trim();
      if (t.isNotEmpty) out.addAll(_splitLong(t));
      buf.clear();
    }

    for (final raw in lines) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      final h = _headingText(t);
      if (h != null) {
        flush();
        out.add(ReaderParagraph(h, heading: true));
        continue;
      }
      if (buf.isEmpty) {
        buf.write(t);
        continue;
      }
      final prev = buf.toString();
      if (_endsHyphen(prev) && RegExp(r'^[a-z]').hasMatch(t)) {
        buf
          ..clear()
          ..write(prev.substring(0, prev.length - 1))
          ..write(t);
      } else if (_endsCjk(prev) || _startsCjk(t)) {
        buf.write(t);
      } else {
        buf
          ..write(' ')
          ..write(t);
      }
    }
    flush();
    return out;
  }

  /// 长段落按句切到约 500 字符，便于本地 LLM 翻译。
  List<ReaderParagraph> _splitLong(String text, {int target = 520}) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    if (t.length <= target * 1.35) return [ReaderParagraph(t)];

    final pieces = <String>[];
    final re = RegExp(r'[^.!?。！？…]+[.!?。！？…]+["”’)\]]*');
    for (final m in re.allMatches(t)) {
      pieces.add(m.group(0)!);
    }
    if (pieces.length <= 1) {
      final out = <ReaderParagraph>[];
      for (var i = 0; i < t.length; i += target) {
        out.add(ReaderParagraph(
            t.substring(i, i + target > t.length ? t.length : i + target)));
      }
      return out;
    }

    final out = <ReaderParagraph>[];
    var buf = '';
    for (final p in pieces) {
      buf = _join(buf, p);
      if (buf.length >= target) {
        out.add(ReaderParagraph(buf.trim()));
        buf = '';
      }
    }
    if (buf.trim().isNotEmpty) out.add(ReaderParagraph(buf.trim()));
    return out;
  }

  static String _joinLines(List<String> lines) {
    final buf = StringBuffer();
    for (final raw in lines) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      if (buf.isEmpty) {
        buf.write(t);
        continue;
      }
      final prev = buf.toString();
      if (_endsHyphen(prev) && RegExp(r'^[a-z]').hasMatch(t)) {
        buf
          ..clear()
          ..write(prev.substring(0, prev.length - 1))
          ..write(t);
      } else if (_endsCjk(prev) || _startsCjk(t)) {
        buf.write(t);
      } else {
        buf
          ..write(' ')
          ..write(t);
      }
    }
    return buf.toString().trim();
  }

  static String? _headingText(String line) {
    final m = RegExp(r'^#{1,3}\s+(.*)$').firstMatch(line);
    return m?.group(1)?.trim();
  }

  static bool _endsSentence(String s) {
    if (s.isEmpty) return true;
    return RegExp(r'[.!?。！？…:：;；]["”’)\]]*$').hasMatch(s);
  }

  static bool _endsCjk(String s) {
    if (s.isEmpty) return false;
    final c = s.codeUnitAt(s.length - 1);
    return c >= 0x3400 && c <= 0x9fff;
  }

  static bool _startsCjk(String s) {
    if (s.isEmpty) return false;
    final c = s.codeUnitAt(0);
    return c >= 0x3400 && c <= 0x9fff;
  }

  static bool _continues(String prev, String next) {
    final p = prev.trimRight();
    final n = next.trimLeft();
    if (p.isEmpty || n.isEmpty) return false;
    if (_endsHyphen(p) || p.endsWith(',') || p.endsWith('，')) return true;
    if (_endsCjk(p) && _startsCjk(n) && !_endsSentence(p)) return true;
    if (_endsSentence(p)) return false;
    final c = n.codeUnitAt(0);
    if (c >= 0x61 && c <= 0x7a) return true; // lowercase
    if (RegExp(r'^[\d(\[{,;:]').hasMatch(n)) return true;
    return false;
  }

  static bool _endsHyphen(String s) {
    if (s.isEmpty) return false;
    final c = s.codeUnitAt(s.length - 1);
    return c == 0x2d ||
        c == 0x2010 ||
        c == 0x2011 ||
        c == 0x2012 ||
        c == 0x2013;
  }

  static String _join(String a, String b) {
    final p = a.trimRight();
    final n = b.trimLeft();
    if (p.isEmpty) return n;
    if (n.isEmpty) return p;
    if (_endsHyphen(p) && RegExp(r'^[a-z]').hasMatch(n)) {
      return '${p.substring(0, p.length - 1)}$n';
    }
    if (_endsCjk(p) || _startsCjk(n)) return '$p$n';
    if (RegExp(r'^[,.;:!?%)\]}]').hasMatch(n)) return '$p$n';
    if (p.endsWith('.') && RegExp(r'^[a-z]').hasMatch(n)) return '$p$n';
    return '$p $n';
  }

  // ── 译文缓存（本地 JSONL，按原文精确匹配）───────────────

  static Map<String, String>? _transCache;

  static Map<String, String> _cache() {
    final loaded = _transCache;
    if (loaded != null) return loaded;
    final map = <String, String>{};
    final f = _dataFile('reader_cache.jsonl');
    if (f != null && f.existsSync()) {
      for (final line in f.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        try {
          final d = json.decode(line) as Map<String, dynamic>;
          final t = '${d['t'] ?? ''}';
          final z = '${d['z'] ?? ''}';
          if (t.isNotEmpty && z.isNotEmpty) map[t] = z;
        } catch (_) {}
      }
    }
    return _transCache = map;
  }

  /// 已缓存的段落译文（没有则返回 null）。
  String? cachedTranslation(String text) => _cache()[text];

  /// 记住一条译文（同时写回本地缓存文件，供下次打开直接显示）。
  void rememberTranslation(String text, String zh) {
    final t = text.trim();
    final z = zh.trim();
    if (t.isEmpty || z.isEmpty) return;
    final map = _cache();
    if (map[t] == z) return;
    map[t] = z;
    final f = _dataFile('reader_cache.jsonl');
    if (f == null) return;
    try {
      f.writeAsStringSync('${json.encode({'t': t, 'z': z})}\n',
          mode: FileMode.append, flush: false);
    } catch (_) {}
  }

  // ── 阅读进度 ───────────────────────────────────────────

  static Map<String, dynamic>? _progress;

  static Map<String, dynamic> _progressMap() {
    final loaded = _progress;
    if (loaded != null) return loaded;
    final f = _dataFile('reader_progress.json');
    if (f != null && f.existsSync()) {
      try {
        return _progress =
            json.decode(f.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {}
    }
    return _progress = <String, dynamic>{};
  }

  int progressOf(String slug) {
    final v = _progressMap()[slug];
    return v is num ? v.toInt() : 0;
  }

  void saveProgress(String slug, int chapterIndex) {
    if (slug.isEmpty) return;
    final map = _progressMap();
    map[slug] = chapterIndex;
    final f = _dataFile('reader_progress.json');
    if (f == null) return;
    try {
      f.writeAsStringSync(json.encode(map), flush: false);
    } catch (_) {}
  }

  // ── 导入（复用 /opt/my_db/tools/import_book）────────────

  static const importTool = '/opt/my_db/tools/import_book';

  Future<int> importBook(
    String path, {
    void Function(String line)? onLog,
  }) async {
    if (!File(importTool).existsSync()) {
      throw StateError('未找到 $importTool');
    }
    final env = Map<String, String>.from(Platform.environment);
    final old = env['LD_LIBRARY_PATH'] ?? '';
    env['LD_LIBRARY_PATH'] = old.isEmpty ? '/opt/my_db' : '/opt/my_db:$old';
    final proc = await Process.start(
      importTool,
      ['/book/cache', path, '--skip-vectors'],
      workingDirectory: '/opt/my_db',
      environment: env,
    );
    void forward(String line) {
      final t = line.trim();
      if (t.isNotEmpty) onLog?.call(t);
    }

    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(forward);
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(forward);
    return proc.exitCode;
  }
}
