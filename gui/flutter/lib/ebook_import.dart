import 'dart:convert';
import 'dart:io';

import 'ffi/wordcard.dart';

/// 电子书解析结果中的一个词条。
final class BookWord {
  BookWord(this.word, this.context, this.definition, this.pos, this.phonetic);
  final String word;
  final String context;
  final String definition; // 中文释义（ECDICT 离线 / LLM 回填，可能为空）
  final String pos;
  final String phonetic;
}

/// 电子书解析结果。
final class BookExtract {
  const BookExtract({
    required this.title,
    required this.author,
    required this.words,
    this.bilingualPath,
  });

  final String title;
  final String author;
  final List<BookWord> words;

  /// 生成的中英文对照文件路径（word/phonetic/pos/translation/context）。
  final String? bilingualPath;

  /// 释义为空的词（需要 LLM 回填）。
  List<String> get undefinedWords =>
      words.where((w) => w.definition.isEmpty).map((w) => w.word).toList();
}

/// 电子书导入：解析**复用**现有 Python 管道（`tools/ebook_extract.py`），
/// 释义优先**离线 ECDICT**，并生成中英文对照文件；未收录词由
/// `tools/ebook_define.py` 异步 LLM 回填。
final class EbookImporter {
  EbookImporter(this.engine);

  final WordCardEngine engine;

  static String? _root() {
    const candidates = ['.', '/opt/WordCard'];
    for (final c in candidates) {
      if (File('$c/tools/ebook_extract.py').existsSync()) return c;
    }
    return null;
  }

  static String _slug(String path) {
    final base = path.split('/').last;
    final name =
        base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
    return name.replaceAll(RegExp(r'[^\w\u4e00-\u9fff-]+'), '_');
  }

  /// 用 zenity 选择电子书文件；取消返回 null。
  Future<String?> pickFile() async {
    final r = await Process.run('zenity', [
      '--file-selection',
      '--title=选择电子书',
      '--file-filter=电子书 | *.epub *.mobi *.azw3 *.pdf *.md *.txt',
      '--file-filter=所有文件 | *',
    ]);
    if (r.exitCode != 0) return null;
    final path = (r.stdout as String).trim();
    return path.isEmpty ? null : path;
  }

  /// 解析电子书并生成中英文对照文件（快速，ECDICT 离线释义）。
  Future<BookExtract> extract(
    String bookPath, {
    int max = 200,
    void Function(String stage)? onStage,
  }) async {
    final root = _root();
    if (root == null) throw StateError('未找到 tools/ebook_extract.py');
    onStage?.call('解析中');
    final slug = _slug(bookPath);
    final bilingual = File('$root/data/books/$slug.tsv');
    bilingual.parent.createSync(recursive: true);
    final tmp = File('${Directory.systemTemp.path}/wordcard_'
        '${DateTime.now().microsecondsSinceEpoch}.json');
    try {
      final r = await Process.run(
        'python3',
        [
          '$root/tools/ebook_extract.py',
          bookPath,
          '--max', '$max',
          '--bilingual', bilingual.path,
          '--out', tmp.path,
        ],
        workingDirectory: root,
      );
      if (r.exitCode != 0 || !tmp.existsSync()) {
        throw StateError('解析失败: ${(r.stderr as String).trim()}');
      }
      final data = json.decode(tmp.readAsStringSync()) as Map<String, dynamic>;
      final words = (data['words'] as List)
          .map((e) => BookWord(
                '${e['w']}',
                '${e['ctx'] ?? ''}',
                '${e['d'] ?? ''}',
                '${e['p'] ?? ''}',
                '${e['ph'] ?? ''}',
              ))
          .toList(growable: false);
      return BookExtract(
        title: '${data['title'] ?? ''}',
        author: '${data['author'] ?? ''}',
        words: words,
        bilingualPath: bilingual.path,
      );
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  /// 把解析出的词条写入 DB（已存在则跳过）。返回新增条数。
  Future<int> importWords(
    BookExtract extract, {
    void Function(int done, int total)? onProgress,
  }) async {
    final total = extract.words.length;
    var added = 0;
    var done = 0;
    for (final w in extract.words) {
      done++;
      if (engine.hasItem(w.word)) continue;
      final id = engine.addItem(
        question: w.word,
        answer: _answer(w),
        explanation: w.context,
        hint: w.phonetic,
        category: 1,
        tags: 'book:${extract.title}',
      );
      if (id != 0) added++;
      if (done % 100 == 0) {
        onProgress?.call(done, total);
        await Future<void>.delayed(Duration.zero);
      }
    }
    engine.save();
    onProgress?.call(total, total);
    return added;
  }

  String _answer(BookWord w) {
    if (w.definition.isEmpty) return '';
    return w.pos.isEmpty ? w.definition : '${w.pos} ${w.definition}';
  }

  /// 对 ECDICT 未收录的词异步生成释义并**动态回填** DB。
  /// 返回成功回填的条数。
  Future<int> defineAll(
    BookExtract extract, {
    void Function(int done, int total)? onProgress,
  }) async {
    final missing = extract.undefinedWords;
    if (missing.isEmpty) return 0;
    final root = _root();
    if (root == null) return 0;
    final wordsFile = File('${Directory.systemTemp.path}/wordcard_words_'
        '${DateTime.now().microsecondsSinceEpoch}');
    wordsFile.writeAsStringSync(missing.join('\n'));
    var updated = 0;
    var done = 0;
    try {
      final proc = await Process.start(
        'python3',
        ['$root/tools/ebook_define.py', '--words', wordsFile.path],
        workingDirectory: root,
      );
      proc.stderr.drain<void>();
      final lines = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        done++;
        try {
          final d = json.decode(line) as Map<String, dynamic>;
          final word = '${d['w']}';
          final def = '${d['d'] ?? ''}';
          final pos = '${d['p'] ?? ''}';
          final id = engine.itemIdByQuestion(word);
          if (id != null && def.isNotEmpty) {
            final answer = pos.isEmpty ? def : '$pos $def';
            if (engine.updateItemAnswer(id, answer)) updated++;
          }
        } catch (_) {
          // 跳过无法解析的行
        }
        onProgress?.call(done, missing.length);
      }
      await proc.exitCode;
      engine.save();
    } finally {
      if (wordsFile.existsSync()) wordsFile.deleteSync();
    }
    return updated;
  }
}
