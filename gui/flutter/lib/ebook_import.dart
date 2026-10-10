import 'dart:convert';
import 'dart:io';

import 'ffi/wordcard.dart';

/// 电子书解析结果中的一个词条。
final class BookWord {
  BookWord(this.word, this.context, this.definition, this.pos);
  final String word;
  final String context;
  String definition; // 中文释义（LLM 异步回填，可能为空）
  String pos;
}

/// 电子书解析结果。
final class BookExtract {
  const BookExtract({
    required this.title,
    required this.author,
    required this.words,
  });

  final String title;
  final String author;
  final List<BookWord> words;
}

/// 电子书导入：解析**复用**现有 Python 管道（`tools/ebook_extract.py`），
/// 释义**异步复用**本地 LLM（`tools/ebook_define.py`），
/// Flutter 端只负责选文件、调脚本、把结果经 FFI 写入同一 DB。
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

  /// 仅解析电子书（快速，不含 LLM 释义）。[onStage] 回调阶段文本。
  Future<BookExtract> extract(
    String bookPath, {
    int max = 200,
    void Function(String stage)? onStage,
  }) async {
    final root = _root();
    if (root == null) throw StateError('未找到 tools/ebook_extract.py');
    onStage?.call('解析中');
    final tmp = _tmp('json');
    try {
      final r = await Process.run(
        'python3',
        ['$root/tools/ebook_extract.py', bookPath, '--max', '$max',
         '--out', tmp.path],
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
              ))
          .toList(growable: true);
      return BookExtract(
        title: '${data['title'] ?? ''}',
        author: '${data['author'] ?? ''}',
        words: words,
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
        explanation: w.context,
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

  /// 异步生成中文释义：逐条从 `ebook_define.py` 读取结果并**动态回填** DB。
  /// 返回成功回填的条数。
  Future<int> defineAll(
    BookExtract extract, {
    void Function(int done, int total)? onProgress,
  }) async {
    final root = _root();
    if (root == null || extract.words.isEmpty) return 0;
    final wordsFile = _tmp('words');
    wordsFile.writeAsStringSync(
      extract.words.map((w) => w.word).join('\n'),
    );
    var updated = 0;
    var done = 0;
    try {
      final proc = await Process.start(
        'python3',
        ['$root/tools/ebook_define.py', '--words', wordsFile.path],
        workingDirectory: root,
      );
      // stderr: 进度（丢弃内容，仅用于不阻塞管道）
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
        onProgress?.call(done, extract.words.length);
      }
      await proc.exitCode;
      engine.save();
    } finally {
      if (wordsFile.existsSync()) wordsFile.deleteSync();
    }
    return updated;
  }

  static File _tmp(String tag) => File(
      '${Directory.systemTemp.path}/wordcard_${tag}_'
      '${DateTime.now().microsecondsSinceEpoch}');
}
